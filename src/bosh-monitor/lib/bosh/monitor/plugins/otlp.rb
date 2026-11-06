require 'json'

module Bosh::Monitor
  module Plugins
    class Otlp < Base
      include HttpRequestHelper

      METRICS_PATH = '/v1/metrics'

      def validate_options
        options.is_a?(Hash) && options['endpoint'].is_a?(String) && !options['endpoint'].empty?
      end

      def run
        unless ::Async::Task.current?
          logger.error('OTLP plugin can only be started when event loop is running')
          return false
        end
        true
      end

      def process(event)
        return unless event.is_a?(Bosh::Monitor::Events::Heartbeat) && event.instance_id

        metrics = event.metrics
        raise PluginError, "Invalid event metrics: Enumerable expected, #{metrics.class} given" unless metrics.is_a?(Enumerable)

        payload = build_otlp_payload(event)
        send_metrics(payload)
      end

      private

      def send_metrics(payload)
        uri = URI.join(options['endpoint'], METRICS_PATH).to_s
        headers = base_headers.merge(options.fetch('headers', {}))
        ca_cert = options['ca_cert']

        send_http_post_request(
          uri: uri,
          request: { head: headers, body: JSON.dump(payload) },
          ca_cert_path: ca_cert,
        )
      end

      def base_headers
        { 'Content-Type' => 'application/json' }
      end

      def build_otlp_payload(heartbeat)
        resource_metrics = {
          'resource' => {
            'attributes' => resource_attributes(heartbeat),
          },
          'scopeMetrics' => [
            {
              'scope' => { 'name' => 'bosh-health-monitor' },
              'metrics' => heartbeat.metrics.map { |m| build_gauge(m) },
            },
          ],
        }
        { 'resourceMetrics' => [resource_metrics] }
      end

      def resource_attributes(heartbeat)
        [
          kv('bosh.deployment', heartbeat.deployment),
          kv('bosh.job',        heartbeat.job),
          kv('bosh.instance_id', heartbeat.instance_id),
          kv('bosh.agent_id',   heartbeat.agent_id),
        ].compact
      end

      def build_gauge(metric)
        {
          'name'  => metric.name,
          'gauge' => {
            'dataPoints' => [
              {
                'timeUnixNano'  => (metric.timestamp.to_i * 1_000_000_000).to_s,
                'asDouble'      => metric.value.to_f,
              },
            ],
          },
        }
      end

      def kv(key, value)
        return nil if value.nil? || value.to_s.empty?
        { 'key' => key, 'value' => { 'stringValue' => value.to_s } }
      end
    end
  end
end
