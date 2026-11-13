require "test_helper"

class Kamander::CloudflareAccessGateTest < ActiveSupport::TestCase
  TEAM = "https://octane.cloudflareaccess.com".freeze
  AUD = "aud-tag-123".freeze
  PUBLIC_HOST = "kamander.example.com".freeze

  setup do
    @key = OpenSSL::PKey::RSA.generate(2048)
    @jwk = JWT::JWK.new(@key, kid: "key-1")
    @fetches = 0
  end

  test "a request through Access with a valid token reaches the app" do
    assert_equal 200, call(host: PUBLIC_HOST, token: token).first
  end

  test "the verified email reaches the app, so it can show who is signed in" do
    seen = nil
    gate = Kamander::CloudflareAccessGate.new(->(env) { seen = env[Kamander::CloudflareAccessGate::IDENTITY]; [ 200, {}, [] ] },
      hosts: [ PUBLIC_HOST ], team_domain: TEAM, audience: AUD, jwks: jwks_loader)

    gate.call(env_for(host: PUBLIC_HOST, token: token))

    assert_equal "someone@example.com", seen
  end

  test "the CF_Authorization cookie works when the header is absent" do
    assert_equal 200, call(host: PUBLIC_HOST, cookie: "CF_Authorization=#{token}").first
  end

  test "no token on the public hostname is refused, so a misconfigured Access app never exposes Kamander" do
    status, _, body = call(host: PUBLIC_HOST)

    assert_equal 403, status
    assert_includes body.join, "Cloudflare Access"
  end

  test "a token for another Access application is refused" do
    assert_equal 403, call(host: PUBLIC_HOST, token: token(aud: "someone-elses-app")).first
  end

  test "a token from another team is refused" do
    assert_equal 403, call(host: PUBLIC_HOST, token: token(iss: "https://evil.cloudflareaccess.com")).first
  end

  test "an expired token is refused" do
    assert_equal 403, call(host: PUBLIC_HOST, token: token(exp: 1.minute.ago.to_i)).first
  end

  test "a token signed with a key Cloudflare didn't publish is refused" do
    forged = JWT.encode(claims, OpenSSL::PKey::RSA.generate(2048), "RS256", kid: "key-1")

    assert_equal 403, call(host: PUBLIC_HOST, token: forged).first
  end

  test "an unsigned token is refused" do
    assert_equal 403, call(host: PUBLIC_HOST, token: JWT.encode(claims, nil, "none")).first
  end

  test "tailnet and localhost requests don't need Access" do
    assert_equal 200, call(host: "box.tailnet.ts.net").first
    assert_equal 200, call(host: "localhost").first
  end

  test "forwarded host headers can't move a public-hostname request out from under the gate" do
    assert_equal 403, call(host: PUBLIC_HOST, env: { "HTTP_X_FORWARDED_HOST" => "localhost" }).first
    assert_equal 403, call(host: PUBLIC_HOST, env: { "HTTP_FORWARDED" => "host=localhost" }).first
  end

  test "anything that came through Cloudflare is gated, whatever its Host header says" do
    assert_equal 403, call(host: "localhost", env: { "HTTP_CF_RAY" => "8a1b2c3d4e5f-IAD" }).first
  end

  test "an incomplete Access setup stops Kamander from booting instead of refusing every request quietly" do
    assert_raises(ArgumentError) { Kamander::CloudflareAccessGate.new(ok_app, hosts: [ PUBLIC_HOST ], team_domain: TEAM, audience: nil) }
    assert_raises(ArgumentError) { Kamander::CloudflareAccessGate.new(ok_app, hosts: [ PUBLIC_HOST ], team_domain: "octane.cloudflareaccess.com", audience: AUD) }
  end

  test "with no Access setup at all, a request through Cloudflare still fails closed" do
    gate = Kamander::CloudflareAccessGate.new(ok_app, hosts: [], team_domain: nil, audience: nil, jwks: jwks_loader)

    assert_equal 403, gate.call(env_for(host: "localhost").merge("HTTP_CF_RAY" => "8a1b2c3d4e5f-IAD")).first
  end

  test "Cloudflare's keys are fetched once; an unknown key id refetches at most once a minute" do
    gate = build_gate
    rotated = -> { JWT.encode(claims, @key, "RS256", kid: "rotated-#{SecureRandom.hex(4)}") }
    2.times { gate.call(env_for(host: PUBLIC_HOST, token: token)) }
    assert_equal 1, @fetches

    5.times { gate.call(env_for(host: PUBLIC_HOST, token: rotated.call)) }
    assert_equal 1, @fetches, "random key ids must not force a fetch per request"

    travel 61.seconds do
      gate.call(env_for(host: PUBLIC_HOST, token: rotated.call))
    end
    assert_equal 2, @fetches
  end

  test "Cloudflare's keys being unreachable refuses the request instead of letting it through" do
    gate = Kamander::CloudflareAccessGate.new(ok_app, hosts: [ PUBLIC_HOST ], team_domain: TEAM, audience: AUD,
      jwks: ->(_options) { raise SocketError, "getaddrinfo failed" })

    assert_equal 403, gate.call(env_for(host: PUBLIC_HOST, token: token)).first
  end

  private

    def call(host:, token: nil, cookie: nil, env: {})
      build_gate.call(env_for(host: host, token: token, cookie: cookie).merge(env))
    end

    def build_gate
      @gate ||= Kamander::CloudflareAccessGate.new(ok_app, hosts: [ PUBLIC_HOST ], team_domain: TEAM, audience: AUD, jwks: jwks_loader)
    end

    def ok_app = ->(_env) { [ 200, {}, [ "ok" ] ] }

    def jwks_loader
      ->(_options) { @fetches += 1; { keys: [ @jwk.export ] } }
    end

    def claims(aud: AUD, iss: TEAM, exp: 10.minutes.from_now.to_i)
      { aud: [ aud ], iss: iss, exp: exp, iat: Time.now.to_i, email: "someone@example.com" }
    end

    def token(**overrides) = JWT.encode(claims(**overrides), @key, "RS256", kid: "key-1")

    def env_for(host:, token: nil, cookie: nil)
      Rack::MockRequest.env_for("https://#{host}/", "HTTP_HOST" => host).tap do |env|
        env["HTTP_CF_ACCESS_JWT_ASSERTION"] = token if token
        env["HTTP_COOKIE"] = cookie if cookie
      end
    end
end
