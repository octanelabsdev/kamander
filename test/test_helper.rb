ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

Dir[Rails.root.join("test/support/**/*.rb")].each { |file| require file }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # turbo-rails normally wires this in via a nested on_load(:action_cable)
    # hook, but that only fires once ActionCable::Channel::Base has actually
    # loaded — which doesn't happen reliably before parallel test workers
    # fork. Requiring/including it explicitly makes assert_turbo_stream_broadcasts
    # available regardless of fork/load order.
    require "turbo/broadcastable/test_helper"
    include Turbo::Broadcastable::TestHelper
  end
end
