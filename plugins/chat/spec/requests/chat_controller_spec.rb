# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::ChatController do
  fab!(:user)
  fab!(:other_user) { Fabricate(:user) }
  fab!(:admin)
  fab!(:category)
  fab!(:chat_channel) { Fabricate(:category_channel, chatable: category) }
  fab!(:dm_chat_channel) { Fabricate(:direct_message_channel, users: [user, other_user, admin]) }
  fab!(:tag)

  MESSAGE_COUNT = 70
  MESSAGE_COUNT.times do |n|
    fab!("message_#{n}") do
      Fabricate(
        :chat_message,
        chat_channel: chat_channel,
        user: other_user,
        message: "message #{n}",
      )
    end
  end

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
  end

  def flag_message(message, flagger, flag_type: ReviewableScore.types[:off_topic])
    Chat::ReviewQueue.new.flag_message(message, Guardian.new(flagger), flag_type)[:reviewable]
  end

  describe "#enable_chat" do
    context "with category as chatable" do
      let!(:category) { Fabricate(:category) }
      let(:channel) { Fabricate(:category_channel, chatable: category) }

      it "ensures created channel can be seen" do
        Guardian.any_instance.expects(:can_join_chat_channel?).with(channel)

        sign_in(admin)
        post "/chat/enable.json", params: { chatable_type: "Category", chatable_id: category.id }
      end

      # TODO: rewrite specs to ensure no exception is raised
      it "ensures existing channel can be seen" do
        Guardian.any_instance.expects(:can_join_chat_channel?)

        sign_in(admin)
        post "/chat/enable.json", params: { chatable_type: "Category", chatable_id: category.id }
      end
    end
  end

  describe "#disable_chat" do
    context "with category as chatable" do
      it "ensures category can be seen" do
        category = Fabricate(:category)
        channel = Fabricate(:category_channel, chatable: category)
        message = Fabricate(:chat_message, chat_channel: channel)

        Guardian.any_instance.expects(:can_join_chat_channel?).with(channel)

        sign_in(admin)
        post "/chat/disable.json", params: { chatable_type: "Category", chatable_id: category.id }
      end
    end
  end

  describe "#rebake" do
    fab!(:chat_message) { Fabricate(:chat_message, chat_channel: chat_channel, user: user) }

    context "as staff" do
      it "rebakes the post" do
        sign_in(Fabricate(:admin))

        expect_enqueued_with(
          job: Jobs::Chat::ProcessMessage,
          args: {
            chat_message_id: chat_message.id,
          },
        ) do
          put "/chat/#{chat_channel.id}/#{chat_message.id}/rebake.json"

          expect(response.status).to eq(200)
        end
      end

      it "does not interfere with core's guardian can_rebake? for posts" do
        sign_in(Fabricate(:admin))
        put "/chat/#{chat_channel.id}/#{chat_message.id}/rebake.json"
        expect(response.status).to eq(200)
        post = Fabricate(:post)
        put "/posts/#{post.id}/rebake.json"
        expect(response.status).to eq(200)
      end

      it "does not rebake the post when channel is read_only" do
        chat_message.chat_channel.update!(status: :read_only)
        sign_in(Fabricate(:admin))

        put "/chat/#{chat_channel.id}/#{chat_message.id}/rebake.json"
        expect(response.status).to eq(403)
      end

      context "when cooked has changed" do
        it "marks the message as dirty" do
          sign_in(Fabricate(:admin))
          chat_message.update!(message: "new content")

          expect_enqueued_with(
            job: Jobs::Chat::ProcessMessage,
            args: {
              chat_message_id: chat_message.id,
            },
          ) do
            put "/chat/#{chat_channel.id}/#{chat_message.id}/rebake.json"

            expect(response.status).to eq(200)
          end
        end
      end
    end

    context "when not staff" do
      it "forbids non staff to rebake" do
        sign_in(Fabricate(:user))
        put "/chat/#{chat_channel.id}/#{chat_message.id}/rebake.json"
        expect(response.status).to eq(403)
      end

      context "as TL3 user" do
        it "forbids less then TL4 user tries to rebake" do
          sign_in(Fabricate(:user, trust_level: TrustLevel[3]))
          put "/chat/#{chat_channel.id}/#{chat_message.id}/rebake.json"
          expect(response.status).to eq(403)
        end
      end

      context "as TL4 user" do
        it "allows TL4 users to rebake" do
          sign_in(Fabricate(:user, trust_level: TrustLevel[4]))
          put "/chat/#{chat_channel.id}/#{chat_message.id}/rebake.json"
          expect(response.status).to eq(200)
        end

        it "does not rebake the post when channel is read_only" do
          chat_message.chat_channel.update!(status: :read_only)
          sign_in(Fabricate(:user, trust_level: TrustLevel[4]))

          put "/chat/#{chat_channel.id}/#{chat_message.id}/rebake.json"
          expect(response.status).to eq(403)
        end
      end
    end
  end

  xdescribe "#edit_message" do
    fab!(:chat_message) { Fabricate(:chat_message, chat_channel: chat_channel, user: user) }

    context "when current user is silenced" do
      before do
        UserSilencer.new(user).silence
        sign_in(user)
      end

      it "raises an invalid request" do
        put "/chat/#{chat_channel.id}/edit/#{chat_message.id}.json", params: { new_message: "Hi" }
        expect(response.status).to eq(422)
      end
    end

    it "errors when a user tries to edit another user's message" do
      sign_in(Fabricate(:user))

      put "/chat/#{chat_channel.id}/edit/#{chat_message.id}.json", params: { new_message: "edit!" }
      expect(response.status).to eq(422)
    end

    it "errors when staff tries to edit another user's message" do
      sign_in(admin)
      new_message = "Vrroooom cars go fast"

      put "/chat/#{chat_channel.id}/edit/#{chat_message.id}.json",
          params: {
            new_message: new_message,
          }
      expect(response.status).to eq(422)
    end

    it "allows a user to edit their own messages" do
      sign_in(user)
      new_message = "Wow markvanlan must be a good programmer"

      put "/chat/#{chat_channel.id}/edit/#{chat_message.id}.json",
          params: {
            new_message: new_message,
          }
      expect(response.status).to eq(200)
      expect(chat_message.reload.message).to eq(new_message)
    end
  end

  describe "react" do
    fab!(:chat_channel) { Fabricate(:category_channel) }
    fab!(:chat_message) { Fabricate(:chat_message, chat_channel: chat_channel, user: user) }
    fab!(:user_membership) do
      Fabricate(:user_chat_channel_membership, chat_channel: chat_channel, user: user)
    end

    fab!(:private_chat_channel) do
      Fabricate(:category_channel, chatable: Fabricate(:private_category, group: Fabricate(:group)))
    end
    fab!(:private_chat_message) do
      Fabricate(:chat_message, chat_channel: private_chat_channel, user: admin)
    end
    fab!(:private_user_membership) do
      Fabricate(:user_chat_channel_membership, chat_channel: private_chat_channel, user: user)
    end

    fab!(:chat_channel_no_memberships) { Fabricate(:category_channel) }
    fab!(:chat_message_no_memberships) do
      Fabricate(:chat_message, chat_channel: chat_channel_no_memberships, user: user)
    end

    it "errors with invalid emoji" do
      sign_in(user)
      put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json",
          params: {
            emoji: 12,
            react_action: "add",
          }
      expect(response.status).to eq(400)
    end

    it "errors with invalid action" do
      sign_in(user)
      put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json",
          params: {
            emoji: ":heart:",
            react_action: "sdf",
          }
      expect(response.status).to eq(400)
    end

    it "creates a membership when reacting to channel without a membership record" do
      sign_in(user)

      expect {
        put "/chat/#{chat_channel_no_memberships.id}/react/#{chat_message_no_memberships.id}.json",
            params: {
              emoji: ":heart:",
              react_action: "add",
            }
      }.to change { Chat::UserChatChannelMembership.count }.by(1)
      expect(response.status).to eq(200)
    end

    it "errors when user tries to react to private channel they can't access" do
      sign_in(user)
      put "/chat/#{private_chat_channel.id}/react/#{private_chat_message.id}.json",
          params: {
            emoji: ":heart:",
            react_action: "add",
          }
      expect(response.status).to eq(403)
    end

    it "errors when the user tries to react to a read_only channel" do
      chat_channel.update(status: :read_only)
      sign_in(user)
      emoji = ":heart:"
      expect {
        put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json",
            params: {
              emoji: emoji,
              react_action: "add",
            }
      }.not_to change { chat_message.reactions.where(user: user, emoji: emoji).count }
      expect(response.status).to eq(403)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("chat.errors.channel_modify_message_disallowed.#{chat_channel.status}"),
      )
    end

    it "errors when user is silenced" do
      UserSilencer.new(user).silence
      sign_in(user)
      put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json",
          params: {
            emoji: ":heart:",
            react_action: "add",
          }
      expect(response.status).to eq(403)
    end

    it "errors when max unique reactions limit is reached" do
      Emoji
        .all
        .map(&:name)
        .take(29)
        .each { |emoji| chat_message.reactions.create(user: user, emoji: emoji) }

      sign_in(user)
      put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json",
          params: {
            emoji: ":wink:",
            react_action: "add",
          }
      expect(response.status).to eq(200)

      put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json",
          params: {
            emoji: ":wave:",
            react_action: "add",
          }
      expect(response.status).to eq(403)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("chat.errors.max_reactions_limit_reached"),
      )
    end

    it "does not error on new duplicate reactions" do
      another_user = Fabricate(:user)
      Emoji
        .all
        .map(&:name)
        .take(29)
        .each { |emoji| chat_message.reactions.create(user: another_user, emoji: emoji) }
      emoji = ":wink:"
      chat_message.reactions.create(user: another_user, emoji: emoji)

      sign_in(user)
      put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json",
          params: {
            emoji: emoji,
            react_action: "add",
          }
      expect(response.status).to eq(200)
    end

    it "adds a reaction record correctly" do
      sign_in(user)
      emoji = ":heart:"
      expect {
        put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json",
            params: {
              emoji: emoji,
              react_action: "add",
            }
      }.to change { chat_message.reactions.where(user: user, emoji: emoji).count }.by(1)
      expect(response.status).to eq(200)
    end

    it "removes a reaction record correctly" do
      sign_in(user)
      emoji = ":heart:"
      chat_message.reactions.create(user: user, emoji: emoji)
      expect {
        put "/chat/#{chat_channel.id}/react/#{chat_message.id}.json",
            params: {
              emoji: emoji,
              react_action: "remove",
            }
      }.to change { chat_message.reactions.where(user: user, emoji: emoji).count }.by(-1)
      expect(response.status).to eq(200)
    end
  end

  describe "#dismiss_retention_reminder" do
    it "errors for anon" do
      post "/chat/dismiss-retention-reminder.json", params: { chatable_type: "Category" }
      expect(response.status).to eq(403)
    end

    it "errors when chatable_type isn't present" do
      sign_in(user)
      post "/chat/dismiss-retention-reminder.json", params: {}
      expect(response.status).to eq(400)
    end

    it "errors when chatable_type isn't a valid option" do
      sign_in(user)
      post "/chat/dismiss-retention-reminder.json", params: { chatable_type: "hi" }
      expect(response.status).to eq(400)
    end

    it "sets `dismissed_channel_retention_reminder` to true" do
      sign_in(user)
      expect {
        post "/chat/dismiss-retention-reminder.json", params: { chatable_type: "Category" }
      }.to change { user.user_option.reload.dismissed_channel_retention_reminder }.to (true)
    end

    it "sets `dismissed_dm_retention_reminder` to true" do
      sign_in(user)
      expect {
        post "/chat/dismiss-retention-reminder.json", params: { chatable_type: "DirectMessage" }
      }.to change { user.user_option.reload.dismissed_dm_retention_reminder }.to (true)
    end

    it "doesn't error if the fields are already true" do
      sign_in(user)
      user.user_option.update(
        dismissed_channel_retention_reminder: true,
        dismissed_dm_retention_reminder: true,
      )
      post "/chat/dismiss-retention-reminder.json", params: { chatable_type: "Category" }
      expect(response.status).to eq(200)

      post "/chat/dismiss-retention-reminder.json", params: { chatable_type: "DirectMessage" }
      expect(response.status).to eq(200)
    end
  end

  describe "#quote_messages" do
    fab!(:channel) { Fabricate(:category_channel, chatable: category, name: "Cool Chat") }
    let(:user2) { Fabricate(:user) }
    let(:message1) do
      Fabricate(
        :chat_message,
        user: user,
        chat_channel: channel,
        message: "an extremely insightful response :)",
      )
    end
    let(:message2) do
      Fabricate(:chat_message, user: user2, chat_channel: channel, message: "says you!")
    end
    let(:message3) { Fabricate(:chat_message, user: user, chat_channel: channel, message: "aw :(") }

    it "returns a 403 if the user can't chat" do
      SiteSetting.chat_allowed_groups = nil
      sign_in(user)
      post "/chat/#{channel.id}/quote.json",
           params: {
             message_ids: [message1.id, message2.id, message3.id],
           }
      expect(response.status).to eq(403)
    end

    it "returns a 403 if the user can't see the channel" do
      category.update!(read_restricted: true)
      group = Fabricate(:group)
      CategoryGroup.create(
        group: group,
        category: category,
        permission_type: CategoryGroup.permission_types[:create_post],
      )
      sign_in(user)
      post "/chat/#{channel.id}/quote.json",
           params: {
             message_ids: [message1.id, message2.id, message3.id],
           }
      expect(response.status).to eq(403)
    end

    it "returns a 404 for a not found channel" do
      channel.destroy
      sign_in(user)
      post "/chat/#{channel.id}/quote.json",
           params: {
             message_ids: [message1.id, message2.id, message3.id],
           }
      expect(response.status).to eq(404)
    end

    it "quotes the message ids provided" do
      sign_in(user)
      post "/chat/#{channel.id}/quote.json",
           params: {
             message_ids: [message1.id, message2.id, message3.id],
           }
      expect(response.status).to eq(200)
      markdown = response.parsed_body["markdown"]
      expect(markdown).to eq(<<~EXPECTED)
      [chat quote="#{user.username};#{message1.id};#{message1.created_at.iso8601}" channel="Cool Chat" channelId="#{channel.id}" multiQuote="true" chained="true"]
      an extremely insightful response :)
      [/chat]

      [chat quote="#{user2.username};#{message2.id};#{message2.created_at.iso8601}" chained="true"]
      says you!
      [/chat]

      [chat quote="#{user.username};#{message3.id};#{message3.created_at.iso8601}" chained="true"]
      aw :(
      [/chat]
      EXPECTED
    end
  end

  describe "#flag" do
    fab!(:admin_chat_message) { Fabricate(:chat_message, user: admin, chat_channel: chat_channel) }
    fab!(:user_chat_message) { Fabricate(:chat_message, user: user, chat_channel: chat_channel) }

    fab!(:admin_dm_message) { Fabricate(:chat_message, user: admin, chat_channel: dm_chat_channel) }

    before do
      sign_in(user)
      Group.refresh_automatic_groups!
    end

    it "creates reviewable" do
      expect {
        put "/chat/flag.json",
            params: {
              chat_message_id: admin_chat_message.id,
              flag_type_id: ReviewableScore.types[:off_topic],
            }
      }.to change { Chat::ReviewableMessage.where(target: admin_chat_message).count }.by(1)
      expect(response.status).to eq(200)
    end

    it "errors for silenced users" do
      UserSilencer.new(user).silence

      put "/chat/flag.json",
          params: {
            chat_message_id: admin_chat_message.id,
            flag_type_id: ReviewableScore.types[:off_topic],
          }
      expect(response.status).to eq(403)
    end

    it "doesn't allow flagging your own message" do
      put "/chat/flag.json",
          params: {
            chat_message_id: user_chat_message.id,
            flag_type_id: ReviewableScore.types[:off_topic],
          }
      expect(response.status).to eq(403)
    end

    it "doesn't allow flagging messages in a read_only channel" do
      user_chat_message.chat_channel.update(status: :read_only)
      put "/chat/flag.json",
          params: {
            chat_message_id: admin_chat_message.id,
            flag_type_id: ReviewableScore.types[:off_topic],
          }

      expect(response.status).to eq(403)
    end

    it "doesn't allow flagging staff if SiteSetting.allow_flagging_staff is false" do
      SiteSetting.allow_flagging_staff = false
      put "/chat/flag.json",
          params: {
            chat_message_id: admin_chat_message.id,
            flag_type_id: ReviewableScore.types[:off_topic],
          }
      expect(response.status).to eq(403)
    end

    it "returns a 429 when the user attempts to flag more than 4 messages  in 1 minute" do
      RateLimiter.enable

      [message_1, message_2, message_3, message_4].each do |message|
        put "/chat/flag.json",
            params: {
              chat_message_id: message.id,
              flag_type_id: ReviewableScore.types[:off_topic],
            }
        expect(response.status).to eq(200)
      end

      put "/chat/flag.json",
          params: {
            chat_message_id: message_5.id,
            flag_type_id: ReviewableScore.types[:off_topic],
          }

      expect(response.status).to eq(429)
    end
  end

  describe "#set_draft" do
    fab!(:chat_channel) { Fabricate(:category_channel) }
    let(:dm_channel) { Fabricate(:direct_message_channel) }

    before { sign_in(user) }

    it "can create and destroy chat drafts" do
      expect {
        post "/chat/drafts.json", params: { chat_channel_id: chat_channel.id, data: "{}" }
      }.to change { Chat::Draft.count }.by(1)

      expect { post "/chat/drafts.json", params: { chat_channel_id: chat_channel.id } }.to change {
        Chat::Draft.count
      }.by(-1)
    end

    it "cannot create chat drafts for a category channel the user cannot access" do
      group = Fabricate(:group)
      private_category = Fabricate(:private_category, group: group)
      chat_channel.update!(chatable: private_category)

      post "/chat/drafts.json", params: { chat_channel_id: chat_channel.id, data: "{}" }
      expect(response.status).to eq(403)

      GroupUser.create!(user: user, group: group)
      expect {
        post "/chat/drafts.json", params: { chat_channel_id: chat_channel.id, data: "{}" }
      }.to change { Chat::Draft.count }.by(1)
    end

    it "cannot create chat drafts for a direct message channel the user cannot access" do
      post "/chat/drafts.json", params: { chat_channel_id: dm_channel.id, data: "{}" }
      expect(response.status).to eq(403)

      Chat::DirectMessageUser.create(user: user, direct_message: dm_channel.chatable)

      expect {
        post "/chat/drafts.json", params: { chat_channel_id: dm_channel.id, data: "{}" }
      }.to change { Chat::Draft.count }.by(1)
    end

    it "cannot create a too long chat draft" do
      SiteSetting.max_chat_draft_length = 100

      post "/chat/drafts.json",
           params: {
             chat_channel_id: chat_channel.id,
             data: { value: "a" * (SiteSetting.max_chat_draft_length + 1) }.to_json,
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to eq([I18n.t("chat.errors.draft_too_long")])
    end
  end

  describe "#message_link" do
    it "ensures message's channel can be seen" do
      channel = Fabricate(:category_channel, chatable: Fabricate(:category))
      message = Fabricate(:chat_message, chat_channel: channel)

      Guardian.any_instance.expects(:can_join_chat_channel?).with(channel)

      sign_in(Fabricate(:user))
      get "/chat/message/#{message.id}.json"
    end
  end
end
