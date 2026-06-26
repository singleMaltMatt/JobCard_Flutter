// Non-web stub — always reports online, no-op listener.
bool get webIsOnline => true;
void listenToConnectivity(void Function(bool online) callback) {}
