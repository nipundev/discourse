import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import concatClass from "discourse/helpers/concat-class";
import formatDate from "discourse/helpers/format-date";
import replaceEmoji from "discourse/helpers/replace-emoji";
import i18n from "discourse-common/helpers/i18n";
import gt from "truth-helpers/helpers/gt";
import ChatThreadParticipants from "../../chat-thread-participants";
import ChatUserAvatar from "../../chat-user-avatar";
import UnreadIndicator from "./item/unread-indicator";

export default class ChatThreadListItem extends Component {
  @service router;

  @action
  openThread(thread) {
    this.router.transitionTo("chat.channel.thread", ...thread.routeModels);
  }

  <template>
    <div
      class={{concatClass
        "chat-thread-list-item"
        (if (gt @thread.tracking.unreadCount 0) "-is-unread")
      }}
      data-thread-id={{@thread.id}}
      ...attributes
    >
      <div class="chat-thread-list-item__main">
        <div
          title={{i18n "chat.thread.view_thread"}}
          role="button"
          class="chat-thread-list-item__open-button"
          {{on "click" (fn this.openThread @thread) passive=true}}
        >
          <div class="chat-thread-list-item__header">
            <div class="chat-thread-list-item__title">
              {{#if @thread.title}}
                {{replaceEmoji @thread.title}}
              {{else}}
                {{replaceEmoji @thread.originalMessage.excerpt}}
              {{/if}}
            </div>
            <div class="chat-thread-list-item__unread-indicator">
              <UnreadIndicator @thread={{@thread}} />
            </div>
          </div>

          <div class="chat-thread-list-item__metadata">

            <div class="chat-thread-list-item__members">
              <ChatUserAvatar
                @user={{@thread.originalMessage.user}}
                @showPresence={{false}}
                @interactive={{false}}
              />
              <ChatThreadParticipants
                @thread={{@thread}}
                @includeOriginalMessageUser={{false}}
                class="chat-thread-list-item__participants"
              />
            </div>

            <div class="chat-thread-list-item__last-reply-timestamp">
              {{#if @thread.preview.lastReplyCreatedAt}}
                {{formatDate
                  @thread.preview.lastReplyCreatedAt
                  leaveAgo="true"
                }}
              {{/if}}
            </div>

          </div>
        </div>
      </div>
    </div>
  </template>
}
