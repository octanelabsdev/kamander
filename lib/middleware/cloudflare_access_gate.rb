require "jwt"
require "net/http"

module Kamander
  # Kamander has no login, so a broken Access application must fail closed here.
  class CloudflareAccessGate
    KEY_TTL = 1.hour
    REFETCH_AFTER = 1.minute

    def initialize(app, hosts: ENV.fetch("CF_ACCESS_HOSTS", "").split(","), team_domain: ENV["CF_ACCESS_TEAM_DOMAIN"],
      audience: ENV["CF_ACCESS_AUD"], jwks: nil)
      @app = app
      @hosts = Array(hosts).map { |host| host.strip.downcase }.reject(&:empty?)
      @team_domain = team_domain.to_s.strip.chomp("/").presence
      @audience = audience.to_s.strip.presence
      @fetch_keys = jwks || method(:fetch_keys)
      @mutex = Mutex.new
      check_setup!
    end

    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless gated?(request)
      return refuse unless authentic?(request)

      @app.call(env)
    end

    private

      def gated?(request)
        request.get_header("HTTP_CF_RAY").present? || @hosts.include?(raw_host(request))
      end

      def authentic?(request)
        token = request.get_header("HTTP_CF_ACCESS_JWT_ASSERTION").presence || request.cookies["CF_Authorization"].presence
        return false unless token && @team_domain && @audience

        JWT.decode(token, nil, true, algorithms: [ "RS256" ], jwks: method(:keys),
          aud: @audience, verify_aud: true, iss: @team_domain, verify_iss: true,
          verify_expiration: true, required_claims: %w[exp aud iss])
        true
      rescue StandardError => e
        Rails.logger.warn("Cloudflare Access: refused #{request.host}#{request.path}: #{e.class}: #{e.message}")
        false
      end

      def keys(options)
        @mutex.synchronize do
          if @keys.nil? || @fetched_at < KEY_TTL.ago || (options[:invalidate] && @fetched_at < REFETCH_AFTER.ago)
            @keys = @fetch_keys.call(options)
            @fetched_at = Time.current
          end
          @keys
        end
      end

      def fetch_keys(_options)
        uri = URI("#{@team_domain}/cdn-cgi/access/certs")
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 3) { |http| http.get(uri.path) }
        raise "certs endpoint returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      # Not request.host: Rack prefers X-Forwarded-Host and Forwarded, which a client can set.
      def raw_host(request)
        request.get_header("HTTP_HOST").to_s.downcase.split(":").first.to_s
      end

      def check_setup!
        return if @hosts.empty?
        raise ArgumentError, "CF_ACCESS_TEAM_DOMAIN and CF_ACCESS_AUD must be set when CF_ACCESS_HOSTS is" unless @team_domain && @audience
        raise ArgumentError, "CF_ACCESS_TEAM_DOMAIN must start with https://" unless @team_domain.start_with?("https://")
      end

      def refuse
        [ 403, { "content-type" => "text/plain" }, [ "Forbidden: this page requires Cloudflare Access.\n" ] ]
      end
  end
end
