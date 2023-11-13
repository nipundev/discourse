# frozen_string_literal: true

module Chat
  class DirectMessageSerializer < ApplicationSerializer
    attribute :group

    has_many :users, serializer: ::Chat::ChatableUserSerializer, embed: :objects

    def users
      users = object.direct_message_users.map(&:user).map { |u| u || Chat::NullUser.new }

      return users - [scope.user] if users.count > 1
      users
    end
  end
end
