export interface SessionMaterial {
  id: number;
  publicKey: ArrayBuffer;
  sealedKey: ArrayBuffer;
}

export const verifySignedMessage: (signedMessage: ArrayBuffer, serverPublicKey: string) => ArrayBuffer;
export const verifySignedWithKey: (signedMessage: ArrayBuffer, publicKey: ArrayBuffer) => ArrayBuffer;
export const createSession: (peerPublicKey: ArrayBuffer) => SessionMaterial;
export const hashPassword: (password: string, salt: string, challenge: string) => ArrayBuffer;
export const setVideoSurface: (surfaceId: string) => void;
export const pushVideoFrame: (codec: string, data: ArrayBuffer, key: boolean, pts: number,
  width: number, height: number) => boolean;
export const getVideoDecoderStatus: () => string;
export const getVideoRenderedFrames: () => number;
export const resetVideoDecoder: () => void;
export const decompressZstd: (data: ArrayBuffer, expectedLength: number) => ArrayBuffer;
export const encrypt: (sessionId: number, payload: ArrayBuffer) => ArrayBuffer;
export const decrypt: (sessionId: number, payload: ArrayBuffer) => ArrayBuffer;
export const destroySession: (sessionId: number) => void;
