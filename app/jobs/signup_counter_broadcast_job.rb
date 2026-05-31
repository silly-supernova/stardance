class SignupCounterBroadcastJob < ApplicationJob
  queue_as :default

  def perform
    count = Rails.cache.fetch("landing/signup_count", expires_in: 30.seconds) { User.count }
    Turbo::StreamsChannel.broadcast_replace_to(
      "signup_counter",
      target: "rsvp_counter",
      partial: "landing/sections/signup_counter",
      locals: { count: count }
    )
  end
end
