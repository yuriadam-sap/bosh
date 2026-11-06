require 'spec_helper'

describe Bosh::Monitor::Plugins::Otlp do
  subject(:plugin) { described_class.new(options) }

  let(:options) do
    { 'endpoint' => 'https://otel-collector.example.com:4318' }
  end

  describe '#validate_options' do
    it 'is valid with a non-empty endpoint' do
      expect(plugin.validate_options).to be_truthy
    end

    it 'is invalid without an endpoint' do
      expect(described_class.new({}).validate_options).to be_falsey
    end

    it 'is invalid when endpoint is empty' do
      expect(described_class.new('endpoint' => '').validate_options).to be_falsey
    end

    it 'is invalid when options is not a hash' do
      expect(described_class.new('not-a-hash').validate_options).to be_falsey
    end
  end

  describe '#run' do
    context "when the event loop isn't running" do
      it 'returns false' do
        expect(plugin.run).to be(false)
      end
    end

    context 'when the event loop is running' do
      include_context Async::RSpec::Reactor

      it 'returns true' do
        expect(plugin.run).to be(true)
      end
    end
  end

  describe '#process' do
    include_context Async::RSpec::Reactor

    before { plugin.run }

    context 'when event is an Alert (not a Heartbeat)' do
      it 'does not send any HTTP request' do
        event = make_alert(timestamp: Time.now.to_i)
        expect(plugin).not_to receive(:send_http_post_request)
        plugin.process(event)
      end
    end

    context 'when event is a Heartbeat without instance_id' do
      it 'does not send any HTTP request' do
        event = make_heartbeat(timestamp: Time.now.to_i, instance_id: nil)
        expect(plugin).not_to receive(:send_http_post_request)
        plugin.process(event)
      end
    end

    context 'when event is a Heartbeat' do
      let(:now) { Time.now.to_i }
      let(:event) { make_heartbeat(timestamp: now) }

      it 'posts OTLP JSON to /v1/metrics' do
        expected_uri = 'https://otel-collector.example.com:4318/v1/metrics'

        expect(plugin).to receive(:send_http_post_request) do |uri:, request:, ca_cert_path:|
          expect(uri).to eq(expected_uri)
          expect(ca_cert_path).to be_nil

          body = JSON.parse(request[:body])
          rm = body.fetch('resourceMetrics').first

          attrs = rm.dig('resource', 'attributes').map { |a| [a['key'], a.dig('value', 'stringValue')] }.to_h
          expect(attrs['bosh.deployment']).to eq(event.deployment)
          expect(attrs['bosh.job']).to eq(event.job)
          expect(attrs['bosh.instance_id']).to eq(event.instance_id)
          expect(attrs['bosh.agent_id']).to eq(event.agent_id)

          metrics = rm.dig('scopeMetrics', 0, 'metrics')
          expect(metrics.size).to eq(event.metrics.size)

          metric = metrics.first
          expect(metric).to have_key('name')
          dp = metric.dig('gauge', 'dataPoints', 0)
          expect(dp).to have_key('timeUnixNano')
          expect(dp['timeUnixNano']).to eq((now * 1_000_000_000).to_s)
          expect(dp).to have_key('asDouble')
        end

        plugin.process(event)
      end

      context 'when custom headers are configured' do
        let(:options) do
          {
            'endpoint' => 'https://otel-collector.example.com:4318',
            'headers'  => { 'Authorization' => 'Bearer my-token' },
          }
        end

        it 'includes custom headers in the request' do
          expect(plugin).to receive(:send_http_post_request) do |uri:, request:, ca_cert_path:|
            expect(request[:head]['Authorization']).to eq('Bearer my-token')
            expect(request[:head]['Content-Type']).to eq('application/json')
          end
          plugin.process(event)
        end
      end

      context 'when ca_cert is configured' do
        let(:options) do
          {
            'endpoint' => 'https://otel-collector.example.com:4318',
            'ca_cert'  => '/var/vcap/jobs/health_monitor/config/otel-ca.crt',
          }
        end

        it 'passes ca_cert_path to the HTTP helper' do
          expect(plugin).to receive(:send_http_post_request) do |uri:, request:, ca_cert_path:|
            expect(ca_cert_path).to eq('/var/vcap/jobs/health_monitor/config/otel-ca.crt')
          end
          plugin.process(event)
        end
      end
    end
  end
end
