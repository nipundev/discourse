import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { inject as service } from "@ember/service";
import concatClass from "discourse/helpers/concat-class";
import formatDate from "discourse/helpers/format-date";
import replaceEmoji from "discourse/helpers/replace-emoji";
import htmlSafe from "discourse-common/helpers/html-safe";
import i18n from "discourse-common/helpers/i18n";
import { bind } from "discourse-common/utils/decorators";
import ChatThreadParticipants from "./chat-thread-participants";
import ChatUserAvatar from "./chat-user-avatar";

export default class ChatMessageThreadIndicator extends Component {
  @service capabilities;
  @service chat;
  @service chatStateManager;
  @service router;
  @service site;

  @tracked isActive = false;

  @action
  setup(element) {
    this.element = element;

    if (this.capabilities.touch) {
      this.element.addEventListener("touchstart", this.onTouchStart, {
        passive: true,
      });
      this.element.addEventListener("touchmove", this.cancelTouch, {
        passive: true,
      });
      this.element.addEventListener("touchend", this.onTouchEnd);
      this.element.addEventListener("touchCancel", this.cancelTouch);
    }

    this.element.addEventListener("click", this.openThread, {
      passive: true,
    });
  }

  @action
  teardown() {
    if (this.capabilities.touch) {
      this.element.removeEventListener("touchstart", this.onTouchStart, {
        passive: true,
      });
      this.element.removeEventListener("touchmove", this.cancelTouch, {
        passive: true,
      });
      this.element.removeEventListener("touchend", this.onTouchEnd);
      this.element.removeEventListener("touchCancel", this.cancelTouch);
    }

    this.element.removeEventListener("click", this.openThread, {
      passive: true,
    });
  }

  @bind
  onTouchStart(event) {
    this.isActive = true;
    event.stopPropagation();

    this.touching = true;
  }

  @bind
  onTouchEnd() {
    this.isActive = false;

    if (this.touching) {
      this.openThread();
    }
  }

  @bind
  cancelTouch() {
    this.isActive = false;
    this.touching = false;
  }

  @bind
  openThread() {
    this.chat.activeMessage = null;

    this.router.transitionTo(
      "chat.channel.thread",
      ...this.args.message.thread.routeModels
    );
  }

  <template>
    <div
      class={{concatClass
        "chat-message-thread-indicator"
        (if this.isActive "-active")
      }}
      {{didInsert this.setup}}
      {{willDestroy this.teardown}}
      role="button"
      title={{i18n "chat.threads.open"}}
    >

      <div class="chat-message-thread-indicator__last-reply-avatar">
        <ChatUserAvatar
          @user={{@message.thread.preview.lastReplyUser}}
          @avatarSize="small"
        />
      </div>

      <div class="chat-message-thread-indicator__last-reply-info">
        <span class="chat-message-thread-indicator__last-reply-username">
          {{@message.thread.preview.lastReplyUser.username}}
        </span>
        <span class="chat-message-thread-indicator__last-reply-timestamp">
          {{formatDate
            @message.thread.preview.lastReplyCreatedAt
            leaveAgo="true"
          }}
        </span>
      </div>
      <div class="chat-message-thread-indicator__replies-count">
        {{i18n "chat.thread.replies" count=@message.thread.preview.replyCount}}
      </div>
      <ChatThreadParticipants @thread={{@message.thread}} />
      <div class="chat-message-thread-indicator__last-reply-excerpt">
        {{replaceEmoji (htmlSafe @message.thread.preview.lastReplyExcerpt)}}
      </div>
    </div>
  </template>
}
