import 'api_client_options.dart';
import 'socket_options.dart';

/// Combined options for initializing FlexDocs services.
class ServiceOptions {
  final ApiClientOptions? apiOptions;
  final SocketServiceOptions? socketOptions;

  const ServiceOptions({
    this.apiOptions,
    this.socketOptions,
  });
}
