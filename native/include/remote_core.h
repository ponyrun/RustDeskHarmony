#ifndef RUSTDESK_HARMONY_REMOTE_CORE_H
#define RUSTDESK_HARMONY_REMOTE_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RemoteCore RemoteCore;

typedef enum RemoteState {
  REMOTE_STATE_IDLE = 0,
  REMOTE_STATE_CONNECTING = 1,
  REMOTE_STATE_AUTHENTICATING = 2,
  REMOTE_STATE_CONNECTED = 3,
  REMOTE_STATE_RECONNECTING = 4,
  REMOTE_STATE_FAILED = 5
} RemoteState;

const char *remote_core_version(void);
RemoteCore *remote_core_create(void);
void remote_core_destroy(RemoteCore *core);
int32_t remote_core_connect(RemoteCore *core, const char *remote_id,
                            const char *id_server, const char *relay_server,
                            const char *api_server, const char *public_key,
                            uint8_t use_websocket);
void remote_core_disconnect(RemoteCore *core);
RemoteState remote_core_state(const RemoteCore *core);
const char *remote_core_last_error(const RemoteCore *core);

#ifdef __cplusplus
}
#endif

#endif
