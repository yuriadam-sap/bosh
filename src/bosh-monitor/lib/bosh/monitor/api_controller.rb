module Bosh::Monitor
  class ApiController < Sinatra::Base
    PULSE_TIMEOUT = 180

    def initialize(heartbeat_interval = 1)
      @heartbeat = Time.now
      @instance_manager = Bosh::Monitor.instance_manager

      Async do |task|
        loop do
          @heartbeat = Time.now
          sleep(heartbeat_interval)
        end
      end

      super
    end

    configure do
      set(:show_exceptions, false)
      set(:raise_errors, false)
      set(:dump_errors, false)
    end

    get '/healthz' do
      body "Last pulse was #{Time.now - @heartbeat} seconds ago"

      if Time.now - @heartbeat > PULSE_TIMEOUT
        logger.error('PULSE TIMEOUT REACHED: queued jobs are not processing in a timely fashion')
        status(500)
      else
        status(200)
      end
    end

    get '/unresponsive_agents' do
      if @instance_manager.director_initial_deployment_sync_done
        JSON.generate(@instance_manager.unresponsive_agents)
      else
        status(503)
      end
    end

    get '/unhealthy_agents' do
      if @instance_manager.director_initial_deployment_sync_done
        JSON.generate(@instance_manager.unhealthy_agents)
      else
        status(503)
      end
    end

    get '/total_available_agents' do
      if @instance_manager.director_initial_deployment_sync_done
        JSON.generate(@instance_manager.total_available_agents)
      else
        status(503)
      end
    end

    get '/failing_instances' do
      if @instance_manager.director_initial_deployment_sync_done
        JSON.generate(@instance_manager.failing_instances)
      else
        status(503)
      end
    end

    get '/stopped_instances' do
      if @instance_manager.director_initial_deployment_sync_done
        JSON.generate(@instance_manager.stopped_instances)
      else
        status(503)
      end
    end

    get '/unknown_instances' do
      if @instance_manager.director_initial_deployment_sync_done
        JSON.generate(@instance_manager.unknown_instances)
      else
        status(503)
      end
    end

    # Resurrector meltdown state endpoints.
    # These endpoints are only available once the resurrector plugin has registered
    # its AlertTracker via Bosh::Monitor.resurrector_alert_tracker.
    # Returns 503 if the resurrector is not configured or initial sync is not done.

    get '/resurrector_meltdown' do
      tracker = Bosh::Monitor.resurrector_alert_tracker
      unless tracker && @instance_manager.director_initial_deployment_sync_done
        status(503)
        next
      end

      result = {}
      @instance_manager.deployments.each_key do |deployment|
        state = tracker.state_for(deployment)
        result[deployment] = if state.meltdown?
                               2
                             elsif state.managed?
                               1
                             else
                               0
                             end
      end
      JSON.generate(result)
    end

    get '/resurrector_unhealthy_count' do
      tracker = Bosh::Monitor.resurrector_alert_tracker
      unless tracker && @instance_manager.director_initial_deployment_sync_done
        status(503)
        next
      end

      result = {}
      @instance_manager.deployments.each_key do |deployment|
        state = tracker.state_for(deployment)
        result[deployment] = state.unhealthy_count
      end
      JSON.generate(result)
    end

    get '/resurrector_unhealthy_percent' do
      tracker = Bosh::Monitor.resurrector_alert_tracker
      unless tracker && @instance_manager.director_initial_deployment_sync_done
        status(503)
        next
      end

      result = {}
      @instance_manager.deployments.each_key do |deployment|
        state = tracker.state_for(deployment)
        result[deployment] = state.unhealthy_percent
      end
      JSON.generate(result)
    end
  end
end
