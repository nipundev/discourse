# frozen_string_literal: true

class Chat::Api::ChannelsInvitesController < Chat::ApiController
  def create
    with_service(Chat::InviteUsersToChannel) do
      on_failed_policy(:can_view_channel) { raise Discourse::InvalidAccess }
      on_model_not_found(:channel) { raise Discourse::NotFound }
    end
  end
end
