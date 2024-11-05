#ifndef PROTOCOLMESSAGES_H
#define PROTOCOLMESSAGES_H

#include <QString>

namespace ProtocolMessages {
constexpr auto DiscoveryRequest = "SatoriEye_DISCOVERY_REQUEST";
constexpr auto DiscoveryResponse = "SatoriEye_DISCOVERY_RESPONSE";
constexpr auto HeartbeatRequest = "SatoriEye_HEARTBEAT_REQUEST";
constexpr auto HeartbeatResponse = "SatoriEye_HEARTBEAT_RESPONSE";
constexpr auto Disconnect = "SatoriEye_DISCONNECT";

constexpr auto Wink = "WINK";
constexpr auto SetModePrefix = "SET_MODE:";
constexpr auto SetModeSuccessPrefix = "SET_MODE_SUCCESS:";

constexpr auto PwmControlPrefix = "CH1:%1CH2:%2CH3:%3";
}

#endif // PROTOCOLMESSAGES_H
