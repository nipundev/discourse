# frozen_string_literal: true

RSpec.describe "Drawer", type: :system do
  fab!(:current_user) { Fabricate(:admin) }
  let(:chat_page) { PageObjects::Pages::Chat.new }
  let(:channel_page) { PageObjects::Pages::ChatChannel.new }
  let(:drawer_page) { PageObjects::Pages::ChatDrawer.new }

  before do
    chat_system_bootstrap
    sign_in(current_user)
  end

  context "when on channel" do
    fab!(:channel) { Fabricate(:chat_channel) }
    fab!(:membership) do
      Fabricate(:user_chat_channel_membership, user: current_user, chat_channel: channel)
    end

    context "when clicking channel title" do
      it "opens channel info page" do
        visit("/")
        chat_page.open_from_header
        drawer_page.open_channel(channel)
        page.find(".chat-channel-title").click

        expect(page).to have_current_path("/chat/c/#{channel.slug}/#{channel.id}/info/members")
      end
    end
  end

  context "when opening" do
    it "uses stored size" do
      visit("/") # we need to visit the page first to set the local storage

      page.execute_script "window.localStorage.setItem('discourse_chat_drawer_size_width','500');"
      page.execute_script "window.localStorage.setItem('discourse_chat_drawer_size_height','500');"

      visit("/")

      chat_page.open_from_header

      expect(page.find(".chat-drawer").native.style("width")).to eq("500px")
      expect(page.find(".chat-drawer").native.style("height")).to eq("500px")
    end

    it "has a default size" do
      visit("/")

      chat_page.open_from_header

      expect(page.find(".chat-drawer").native.style("width")).to eq("400px")
      expect(page.find(".chat-drawer").native.style("height")).to eq("530px")
    end
  end

  context "when toggling open/close" do
    it "toggles a css class on body" do
      visit("/")

      chat_page.open_from_header

      expect(page.find("body.chat-drawer-active")).to be_visible

      drawer_page.close

      expect(page.find("body:not(.chat-drawer-active)")).to be_visible
    end
  end

  context "when closing the drawer" do
    fab!(:channel_1) { Fabricate(:chat_channel) }
    fab!(:message_1) { Fabricate(:chat_message, chat_channel: channel_1) }

    before { channel_1.add(current_user) }

    it "resets the active message" do
      visit("/")
      chat_page.open_from_header
      drawer_page.open_channel(channel_1)
      channel_page.hover_message(message_1)

      expect(page).to have_css(".chat-message-actions-container", visible: :all)

      drawer_page.close

      expect(page).to have_no_css(".chat-message-actions-container")
    end
  end

  context "when clicking the drawer's header" do
    it "collapses the drawer" do
      visit("/")
      chat_page.open_from_header
      expect(page).to have_selector(".chat-drawer.is-expanded")

      page.find(".chat-drawer-header").click

      expect(page).to have_selector(".chat-drawer:not(.is-expanded)")
    end
  end

  context "when going from drawer to full page" do
    fab!(:channel_1) { Fabricate(:chat_channel) }
    fab!(:channel_2) { Fabricate(:chat_channel) }
    fab!(:user_1) { Fabricate(:user) }

    before do
      channel_1.add(current_user)
      channel_2.add(current_user)
      channel_1.add(user_1)
      channel_2.add(user_1)
    end

    it "correctly resets subscriptions" do
      visit("/")

      chat_page.open_from_header
      drawer_page.maximize
      chat_page.minimize_full_page
      drawer_page.maximize

      Fabricate(
        :chat_message,
        chat_channel: channel_1,
        user: user_1,
        use_service: true,
        message: "onlyonce",
      )

      expect(page).to have_content("onlyonce", count: 1)

      chat_page.visit_channel(channel_2)

      expect(page).to have_content("onlyonce", count: 0)
    end
  end

  context "when subfolder install" do
    fab!(:channel) { Fabricate(:chat_channel) }

    before do
      channel.add(current_user)
      set_subfolder "/discuss"
    end

    it "works to go from full page to drawer" do
      visit("/discuss/chat")
      chat_page.minimize_full_page

      expect(drawer_page).to have_open_channel(channel)
    end
  end
end
