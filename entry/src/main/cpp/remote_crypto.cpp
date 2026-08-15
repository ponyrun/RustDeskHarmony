#include "napi/native_api.h"
#include "sodium.h"
#include "zstd.h"
#include "multimedia/player_framework/native_avbuffer.h"
#include "multimedia/player_framework/native_avcodec_videodecoder.h"
#include "multimedia/player_framework/native_avformat.h"
#include "native_window/external_window.h"

#include <array>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <deque>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

struct CryptoSession {
    std::array<unsigned char, crypto_secretbox_KEYBYTES> key{};
    uint64_t encryptSequence = 0;
    uint64_t decryptSequence = 0;
};

std::mutex gSessionMutex;
std::unordered_map<int64_t, CryptoSession> gSessions;
int64_t gNextSessionId = 1;

struct EncodedFrame {
    std::vector<unsigned char> data;
    int64_t pts = 0;
    bool key = false;
};

struct InputSlot {
    uint32_t index = 0;
    OH_AVBuffer *buffer = nullptr;
};

struct VideoDecoderState {
    std::mutex mutex;
    OH_AVCodec *codec = nullptr;
    OHNativeWindow *window = nullptr;
    uint64_t surfaceId = 0;
    std::string codecName;
    std::string status = "等待视频 Surface";
    std::deque<EncodedFrame> frames;
    std::deque<InputSlot> slots;
    uint64_t renderedFrames = 0;
    bool awaitingKeyFrame = true;
};

VideoDecoderState gVideo;

napi_value Throw(napi_env env, const char *message)
{
    napi_throw_error(env, nullptr, message);
    return nullptr;
}

bool ReadArrayBuffer(napi_env env, napi_value value, std::vector<unsigned char> &out)
{
    bool isArrayBuffer = false;
    if (napi_is_arraybuffer(env, value, &isArrayBuffer) != napi_ok || !isArrayBuffer) {
        return false;
    }
    void *data = nullptr;
    size_t length = 0;
    if (napi_get_arraybuffer_info(env, value, &data, &length) != napi_ok) {
        return false;
    }
    const auto *bytes = static_cast<const unsigned char *>(data);
    out.assign(bytes, bytes + length);
    return true;
}

bool ReadString(napi_env env, napi_value value, std::string &out)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::vector<char> buffer(length + 1, 0);
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
        return false;
    }
    out.assign(buffer.data(), length);
    return true;
}

napi_value CreateArrayBuffer(napi_env env, const unsigned char *data, size_t length)
{
    void *destination = nullptr;
    napi_value result = nullptr;
    if (napi_create_arraybuffer(env, length, &destination, &result) != napi_ok) {
        return Throw(env, "Unable to allocate native result buffer");
    }
    if (length > 0) {
        std::memcpy(destination, data, length);
    }
    return result;
}

void SetObjectProperty(napi_env env, napi_value object, const char *name, napi_value value)
{
    napi_set_named_property(env, object, name, value);
}

std::array<unsigned char, crypto_secretbox_NONCEBYTES> Nonce(uint64_t sequence)
{
    std::array<unsigned char, crypto_secretbox_NONCEBYTES> nonce{};
    for (size_t index = 0; index < sizeof(sequence); ++index) {
        nonce[index] = static_cast<unsigned char>((sequence >> (index * 8U)) & 0xffU);
    }
    return nonce;
}

const char *VideoMime(const std::string &codec)
{
    if (codec == "vp9") return "video/x-vnd.on2.vp9";
    if (codec == "vp8") return "video/x-vnd.on2.vp8";
    if (codec == "h264") return "video/avc";
    if (codec == "h265") return "video/hevc";
    return nullptr;
}

void SubmitFrame(OH_AVCodec *codec, const InputSlot &slot, EncodedFrame frame)
{
    if (codec == nullptr || slot.buffer == nullptr) return;
    uint8_t *destination = OH_AVBuffer_GetAddr(slot.buffer);
    const int32_t capacity = OH_AVBuffer_GetCapacity(slot.buffer);
    if (destination == nullptr || capacity < 0 || frame.data.size() > static_cast<size_t>(capacity)) {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        gVideo.status = "系统解码器输入缓冲区不足";
        return;
    }
    std::memcpy(destination, frame.data.data(), frame.data.size());
    OH_AVCodecBufferAttr attributes{};
    attributes.pts = frame.pts;
    attributes.size = static_cast<int32_t>(frame.data.size());
    attributes.offset = 0;
    attributes.flags = frame.key ? AVCODEC_BUFFER_FLAGS_SYNC_FRAME : AVCODEC_BUFFER_FLAGS_NONE;
    if (OH_AVBuffer_SetBufferAttr(slot.buffer, &attributes) != AV_ERR_OK ||
        OH_VideoDecoder_PushInputBuffer(codec, slot.index) != AV_ERR_OK) {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        gVideo.status = "向 HarmonyOS VideoDecoder 提交帧失败";
    }
}

void OnVideoError(OH_AVCodec *, int32_t errorCode, void *)
{
    std::lock_guard<std::mutex> lock(gVideo.mutex);
    gVideo.status = "HarmonyOS VideoDecoder 错误：" + std::to_string(errorCode);
}

void OnVideoStreamChanged(OH_AVCodec *, OH_AVFormat *, void *)
{
}

void OnVideoNeedInput(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer, void *)
{
    EncodedFrame frame;
    bool hasFrame = false;
    {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        if (!gVideo.frames.empty()) {
            frame = std::move(gVideo.frames.front());
            gVideo.frames.pop_front();
            hasFrame = true;
        } else {
            gVideo.slots.push_back({index, buffer});
        }
    }
    if (hasFrame) SubmitFrame(codec, {index, buffer}, std::move(frame));
}

void OnVideoOutput(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *, void *)
{
    const OH_AVErrCode result = OH_VideoDecoder_RenderOutputBuffer(codec, index);
    std::lock_guard<std::mutex> lock(gVideo.mutex);
    if (result == AV_ERR_OK) {
        ++gVideo.renderedFrames;
        gVideo.status = "正在硬件解码并渲染 " + gVideo.codecName + " 视频";
    } else {
        gVideo.status = "HarmonyOS 视频 Surface 渲染失败";
    }
}

void StopVideoDecoder()
{
    OH_AVCodec *codec = nullptr;
    OHNativeWindow *window = nullptr;
    {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        codec = gVideo.codec;
        window = gVideo.window;
        gVideo.codec = nullptr;
        gVideo.window = nullptr;
        gVideo.codecName.clear();
        gVideo.frames.clear();
        gVideo.slots.clear();
        gVideo.renderedFrames = 0;
    }
    if (codec != nullptr) {
        OH_VideoDecoder_Stop(codec);
        OH_VideoDecoder_Destroy(codec);
    }
    if (window != nullptr) OH_NativeWindow_DestroyNativeWindow(window);
}

bool StartVideoDecoder(const std::string &codecName, int32_t width, int32_t height)
{
    const char *mime = VideoMime(codecName);
    if (mime == nullptr) return false;
    uint64_t surfaceId = 0;
    {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        if (gVideo.codec != nullptr && gVideo.codecName == codecName) return true;
        surfaceId = gVideo.surfaceId;
    }
    if (surfaceId == 0) {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        gVideo.status = "视频已到达，等待会话页面 Surface";
        return false;
    }
    StopVideoDecoder();
    OHNativeWindow *window = nullptr;
    if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &window) != 0 || window == nullptr) {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        gVideo.status = "无法取得 HarmonyOS 视频 Surface";
        return false;
    }
    OH_AVCodec *decoder = OH_VideoDecoder_CreateByMime(mime);
    if (decoder == nullptr) {
        OH_NativeWindow_DestroyNativeWindow(window);
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        gVideo.status = "设备不支持 " + codecName + " 系统解码器";
        return false;
    }
    OH_AVCodecCallback callbacks{OnVideoError, OnVideoStreamChanged, OnVideoNeedInput, OnVideoOutput};
    OH_AVFormat *format = OH_AVFormat_CreateVideoFormat(mime, width > 0 ? width : 1920,
                                                        height > 0 ? height : 1080);
    const bool ready = format != nullptr &&
        OH_VideoDecoder_RegisterCallback(decoder, callbacks, nullptr) == AV_ERR_OK &&
        OH_VideoDecoder_Configure(decoder, format) == AV_ERR_OK &&
        OH_VideoDecoder_SetSurface(decoder, window) == AV_ERR_OK &&
        OH_VideoDecoder_Prepare(decoder) == AV_ERR_OK &&
        OH_VideoDecoder_Start(decoder) == AV_ERR_OK;
    if (format != nullptr) OH_AVFormat_Destroy(format);
    if (!ready) {
        OH_VideoDecoder_Destroy(decoder);
        OH_NativeWindow_DestroyNativeWindow(window);
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        gVideo.status = "启动 " + codecName + " 系统解码器失败";
        return false;
    }
    {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        gVideo.codec = decoder;
        gVideo.window = window;
        gVideo.codecName = codecName;
        gVideo.status = "已启动 " + codecName + " 硬件解码器";
    }
    return true;
}

napi_value VerifySignedMessage(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2) {
        return Throw(env, "verifySignedMessage expects signed bytes and a base64 public key");
    }

    std::vector<unsigned char> signedMessage;
    std::string publicKeyBase64;
    if (!ReadArrayBuffer(env, args[0], signedMessage) || !ReadString(env, args[1], publicKeyBase64)) {
        return Throw(env, "Invalid verifySignedMessage arguments");
    }
    if (signedMessage.size() < crypto_sign_BYTES) {
        return Throw(env, "Signed RustDesk message is too short");
    }

    std::array<unsigned char, crypto_sign_PUBLICKEYBYTES> publicKey{};
    size_t publicKeyLength = 0;
    if (sodium_base642bin(publicKey.data(), publicKey.size(), publicKeyBase64.c_str(),
                          publicKeyBase64.size(), nullptr, &publicKeyLength, nullptr,
                          sodium_base64_VARIANT_ORIGINAL) != 0 ||
        publicKeyLength != publicKey.size()) {
        return Throw(env, "Invalid RustDesk Server Pro public key");
    }

    std::vector<unsigned char> message(signedMessage.size() - crypto_sign_BYTES);
    unsigned long long messageLength = 0;
    if (crypto_sign_open(message.data(), &messageLength, signedMessage.data(),
                         signedMessage.size(), publicKey.data()) != 0) {
        return Throw(env, "RustDesk signature verification failed");
    }
    message.resize(static_cast<size_t>(messageLength));
    return CreateArrayBuffer(env, message.data(), message.size());
}

napi_value VerifySignedWithKey(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::vector<unsigned char> signedMessage;
    std::vector<unsigned char> publicKey;
    if (argc != 2 || !ReadArrayBuffer(env, args[0], signedMessage) ||
        !ReadArrayBuffer(env, args[1], publicKey) ||
        publicKey.size() != crypto_sign_PUBLICKEYBYTES || signedMessage.size() < crypto_sign_BYTES) {
        return Throw(env, "verifySignedWithKey expects signed bytes and a 32-byte public key");
    }

    std::vector<unsigned char> message(signedMessage.size() - crypto_sign_BYTES);
    unsigned long long messageLength = 0;
    if (crypto_sign_open(message.data(), &messageLength, signedMessage.data(),
                         signedMessage.size(), publicKey.data()) != 0) {
        return Throw(env, "RustDesk peer signature verification failed");
    }
    message.resize(static_cast<size_t>(messageLength));
    return CreateArrayBuffer(env, message.data(), message.size());
}

napi_value CreateSession(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::vector<unsigned char> peerPublicKey;
    if (argc != 1 || !ReadArrayBuffer(env, args[0], peerPublicKey) ||
        peerPublicKey.size() != crypto_box_PUBLICKEYBYTES) {
        return Throw(env, "createSession expects a 32-byte peer public key");
    }

    std::array<unsigned char, crypto_box_PUBLICKEYBYTES> publicKey{};
    std::array<unsigned char, crypto_box_SECRETKEYBYTES> secretKey{};
    std::array<unsigned char, crypto_box_NONCEBYTES> nonce{};
    CryptoSession session;
    crypto_box_keypair(publicKey.data(), secretKey.data());
    randombytes_buf(session.key.data(), session.key.size());

    std::array<unsigned char, crypto_secretbox_KEYBYTES + crypto_box_MACBYTES> sealedKey{};
    if (crypto_box_easy(sealedKey.data(), session.key.data(), session.key.size(), nonce.data(),
                        peerPublicKey.data(), secretKey.data()) != 0) {
        sodium_memzero(secretKey.data(), secretKey.size());
        return Throw(env, "Unable to create RustDesk session key");
    }
    sodium_memzero(secretKey.data(), secretKey.size());

    int64_t sessionId = 0;
    {
        std::lock_guard<std::mutex> lock(gSessionMutex);
        sessionId = gNextSessionId++;
        gSessions.emplace(sessionId, session);
    }
    sodium_memzero(session.key.data(), session.key.size());

    napi_value result = nullptr;
    napi_create_object(env, &result);
    napi_value id = nullptr;
    napi_create_int64(env, sessionId, &id);
    SetObjectProperty(env, result, "id", id);
    SetObjectProperty(env, result, "publicKey",
                      CreateArrayBuffer(env, publicKey.data(), publicKey.size()));
    SetObjectProperty(env, result, "sealedKey",
                      CreateArrayBuffer(env, sealedKey.data(), sealedKey.size()));
    return result;
}

napi_value HashPassword(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string password;
    std::string salt;
    std::string challenge;
    if (argc != 3 || !ReadString(env, args[0], password) || !ReadString(env, args[1], salt) ||
        !ReadString(env, args[2], challenge)) {
        return Throw(env, "hashPassword expects password, salt and challenge strings");
    }
    if (password.empty()) {
        return CreateArrayBuffer(env, nullptr, 0);
    }

    std::array<unsigned char, crypto_hash_sha256_BYTES> salted{};
    crypto_hash_sha256_state first{};
    crypto_hash_sha256_init(&first);
    crypto_hash_sha256_update(&first,
        reinterpret_cast<const unsigned char *>(password.data()), password.size());
    crypto_hash_sha256_update(&first,
        reinterpret_cast<const unsigned char *>(salt.data()), salt.size());
    crypto_hash_sha256_final(&first, salted.data());

    std::array<unsigned char, crypto_hash_sha256_BYTES> response{};
    crypto_hash_sha256_state second{};
    crypto_hash_sha256_init(&second);
    crypto_hash_sha256_update(&second, salted.data(), salted.size());
    crypto_hash_sha256_update(&second,
        reinterpret_cast<const unsigned char *>(challenge.data()), challenge.size());
    crypto_hash_sha256_final(&second, response.data());
    sodium_memzero(salted.data(), salted.size());
    return CreateArrayBuffer(env, response.data(), response.size());
}

napi_value SetVideoSurface(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string surface;
    if (argc != 1 || !ReadString(env, args[0], surface)) {
        return Throw(env, "setVideoSurface expects a HarmonyOS surface id");
    }
    uint64_t surfaceId = 0;
    try {
        surfaceId = surface.empty() ? 0 : std::stoull(surface);
    } catch (...) {
        return Throw(env, "Invalid HarmonyOS surface id");
    }
    StopVideoDecoder();
    {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        gVideo.surfaceId = surfaceId;
        gVideo.awaitingKeyFrame = surfaceId != 0;
        gVideo.status = surfaceId == 0 ? "等待视频 Surface" : "视频 Surface 已就绪";
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value PushVideoFrame(napi_env env, napi_callback_info info)
{
    size_t argc = 6;
    napi_value args[6] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string codecName;
    std::vector<unsigned char> data;
    bool key = false;
    int64_t pts = 0;
    int32_t width = 0;
    int32_t height = 0;
    if (argc != 6 || !ReadString(env, args[0], codecName) || !ReadArrayBuffer(env, args[1], data) ||
        napi_get_value_bool(env, args[2], &key) != napi_ok ||
        napi_get_value_int64(env, args[3], &pts) != napi_ok ||
        napi_get_value_int32(env, args[4], &width) != napi_ok ||
        napi_get_value_int32(env, args[5], &height) != napi_ok) {
        return Throw(env, "Invalid pushVideoFrame arguments");
    }
    bool accepted = false;
    {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        if (gVideo.awaitingKeyFrame && !key) {
            napi_value result = nullptr;
            napi_get_boolean(env, false, &result);
            return result;
        }
        if (key) gVideo.awaitingKeyFrame = false;
    }
    if (!data.empty() && StartVideoDecoder(codecName, width, height)) {
        InputSlot slot;
        bool hasSlot = false;
        EncodedFrame frame{std::move(data), pts, key};
        {
            std::lock_guard<std::mutex> lock(gVideo.mutex);
            if (!gVideo.slots.empty()) {
                slot = gVideo.slots.front();
                gVideo.slots.pop_front();
                hasSlot = true;
            } else {
                while (gVideo.frames.size() >= 4) gVideo.frames.pop_front();
                gVideo.frames.push_back(std::move(frame));
            }
            accepted = true;
        }
        if (hasSlot) SubmitFrame(gVideo.codec, slot, std::move(frame));
    }
    napi_value result = nullptr;
    napi_get_boolean(env, accepted, &result);
    return result;
}

napi_value GetVideoDecoderStatus(napi_env env, napi_callback_info)
{
    std::string status;
    {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        status = gVideo.status;
        if (gVideo.renderedFrames > 0) status += " · " + std::to_string(gVideo.renderedFrames) + " 帧";
    }
    napi_value result = nullptr;
    napi_create_string_utf8(env, status.c_str(), status.size(), &result);
    return result;
}

napi_value GetVideoRenderedFrames(napi_env env, napi_callback_info)
{
    uint64_t renderedFrames = 0;
    {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        renderedFrames = gVideo.renderedFrames;
    }
    napi_value result = nullptr;
    napi_create_int64(env, static_cast<int64_t>(renderedFrames), &result);
    return result;
}

napi_value ResetVideoDecoder(napi_env env, napi_callback_info)
{
    StopVideoDecoder();
    {
        std::lock_guard<std::mutex> lock(gVideo.mutex);
        gVideo.surfaceId = 0;
        gVideo.awaitingKeyFrame = true;
        gVideo.status = "等待视频 Surface";
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value DecompressZstd(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::vector<unsigned char> input;
    int64_t expectedLength = 0;
    constexpr int64_t kMaximumCursorBytes = 16 * 1024 * 1024;
    if (argc != 2 || !ReadArrayBuffer(env, args[0], input) ||
        napi_get_value_int64(env, args[1], &expectedLength) != napi_ok ||
        expectedLength <= 0 || expectedLength > kMaximumCursorBytes) {
        return Throw(env, "Invalid RustDesk cursor decompression arguments");
    }
    std::vector<unsigned char> output(static_cast<size_t>(expectedLength));
    const size_t decoded = ZSTD_decompress(output.data(), output.size(), input.data(), input.size());
    if (ZSTD_isError(decoded) || decoded != output.size()) {
        return Throw(env, "RustDesk cursor Zstandard decompression failed");
    }
    return CreateArrayBuffer(env, output.data(), output.size());
}

napi_value Transform(napi_env env, napi_callback_info info, bool encrypt)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t sessionId = 0;
    std::vector<unsigned char> input;
    if (argc != 2 || napi_get_value_int64(env, args[0], &sessionId) != napi_ok ||
        !ReadArrayBuffer(env, args[1], input)) {
        return Throw(env, "Invalid RustDesk crypto transform arguments");
    }

    std::vector<unsigned char> output;
    std::lock_guard<std::mutex> lock(gSessionMutex);
    auto session = gSessions.find(sessionId);
    if (session == gSessions.end()) {
        return Throw(env, "RustDesk crypto session no longer exists");
    }

    if (encrypt) {
        const auto nonce = Nonce(++session->second.encryptSequence);
        output.resize(input.size() + crypto_secretbox_MACBYTES);
        if (crypto_secretbox_easy(output.data(), input.data(), input.size(), nonce.data(),
                                  session->second.key.data()) != 0) {
            return Throw(env, "RustDesk packet encryption failed");
        }
    } else {
        if (input.size() < crypto_secretbox_MACBYTES) {
            return Throw(env, "Encrypted RustDesk packet is too short");
        }
        const auto nonce = Nonce(++session->second.decryptSequence);
        output.resize(input.size() - crypto_secretbox_MACBYTES);
        if (crypto_secretbox_open_easy(output.data(), input.data(), input.size(), nonce.data(),
                                       session->second.key.data()) != 0) {
            return Throw(env, "RustDesk packet decryption failed");
        }
    }
    return CreateArrayBuffer(env, output.data(), output.size());
}

napi_value Encrypt(napi_env env, napi_callback_info info)
{
    return Transform(env, info, true);
}

napi_value Decrypt(napi_env env, napi_callback_info info)
{
    return Transform(env, info, false);
}

napi_value DestroySession(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int64_t sessionId = 0;
    if (argc == 1 && napi_get_value_int64(env, args[0], &sessionId) == napi_ok) {
        std::lock_guard<std::mutex> lock(gSessionMutex);
        auto session = gSessions.find(sessionId);
        if (session != gSessions.end()) {
            sodium_memzero(session->second.key.data(), session->second.key.size());
            gSessions.erase(session);
        }
    }
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value Init(napi_env env, napi_value exports)
{
    if (sodium_init() < 0) {
        return Throw(env, "libsodium initialization failed");
    }
    napi_property_descriptor descriptors[] = {
        {"verifySignedMessage", nullptr, VerifySignedMessage, nullptr, nullptr, nullptr,
         napi_default, nullptr},
        {"verifySignedWithKey", nullptr, VerifySignedWithKey, nullptr, nullptr, nullptr,
         napi_default, nullptr},
        {"createSession", nullptr, CreateSession, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"hashPassword", nullptr, HashPassword, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setVideoSurface", nullptr, SetVideoSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pushVideoFrame", nullptr, PushVideoFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVideoDecoderStatus", nullptr, GetVideoDecoderStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVideoRenderedFrames", nullptr, GetVideoRenderedFrames, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resetVideoDecoder", nullptr, ResetVideoDecoder, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"decompressZstd", nullptr, DecompressZstd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"encrypt", nullptr, Encrypt, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"decrypt", nullptr, Decrypt, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroySession", nullptr, DestroySession, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}

} // namespace

static napi_module remoteCryptoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "remote_crypto",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

extern "C" __attribute__((constructor)) void RegisterRemoteCryptoModule()
{
    napi_module_register(&remoteCryptoModule);
}
