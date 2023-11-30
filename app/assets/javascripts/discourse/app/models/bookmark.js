import { computed } from "@ember/object";
import { none } from "@ember/object/computed";
import { capitalize } from "@ember/string";
import { Promise } from "rsvp";
import { ajax } from "discourse/lib/ajax";
import { formattedReminderTime } from "discourse/lib/bookmark";
import { longDate } from "discourse/lib/formatter";
import { applyModelTransformations } from "discourse/lib/model-transformers";
import RestModel from "discourse/models/rest";
import Topic from "discourse/models/topic";
import User from "discourse/models/user";
import getURL from "discourse-common/lib/get-url";
import discourseComputed from "discourse-common/utils/decorators";
import I18n from "discourse-i18n";
import Category from "./category";

export const AUTO_DELETE_PREFERENCES = {
  NEVER: 0,
  CLEAR_REMINDER: 3,
  WHEN_REMINDER_SENT: 1,
  ON_OWNER_REPLY: 2,
};

export const NO_REMINDER_ICON = "bookmark";
export const WITH_REMINDER_ICON = "discourse-bookmark-clock";

const Bookmark = RestModel.extend({
  newBookmark: none("id"),

  @computed
  get url() {
    return getURL(`/bookmarks/${this.id}`);
  },

  destroy() {
    if (this.newBookmark) {
      return Promise.resolve();
    }

    return ajax(this.url, {
      type: "DELETE",
    });
  },

  attachedTo() {
    return {
      target: this.bookmarkable_type.toLowerCase(),
      targetId: this.bookmarkable_id,
    };
  },

  togglePin() {
    if (this.newBookmark) {
      return Promise.resolve();
    }

    return ajax(this.url + "/toggle_pin", {
      type: "PUT",
    });
  },

  pinAction() {
    return this.pinned ? "unpin" : "pin";
  },

  @discourseComputed("highest_post_number", "url")
  lastPostUrl(highestPostNumber) {
    return this.urlForPostNumber(highestPostNumber);
  },

  // Helper to build a Url with a post number
  urlForPostNumber(postNumber) {
    let url = getURL(`/t/${this.topic_id}`);
    if (postNumber > 0) {
      url += `/${postNumber}`;
    }
    return url;
  },

  // returns createdAt if there's no bumped date
  @discourseComputed("bumped_at", "createdAt")
  bumpedAt(bumped_at, createdAt) {
    if (bumped_at) {
      return new Date(bumped_at);
    } else {
      return createdAt;
    }
  },

  @discourseComputed("bumpedAt", "createdAt")
  bumpedAtTitle(bumpedAt, createdAt) {
    const BUMPED_FORMAT = "YYYY-MM-DDTHH:mm:ss";
    if (moment(bumpedAt).isValid() && moment(createdAt).isValid()) {
      const bumpedAtStr = moment(bumpedAt).format(BUMPED_FORMAT);
      const createdAtStr = moment(createdAt).format(BUMPED_FORMAT);

      return bumpedAtStr !== createdAtStr
        ? `${I18n.t("topic.created_at", {
            date: longDate(createdAt),
          })}\n${I18n.t("topic.bumped_at", { date: longDate(bumpedAt) })}`
        : I18n.t("topic.created_at", { date: longDate(createdAt) });
    }
  },

  @discourseComputed("created_at")
  createdAt(created_at) {
    return new Date(created_at);
  },

  @discourseComputed("tags")
  visibleListTags(tags) {
    if (!tags || !this.siteSettings.suppress_overlapping_tags_in_list) {
      return tags;
    }

    const title = this.title;
    const newTags = [];

    tags.forEach(function (tag) {
      if (!title.toLowerCase().includes(tag)) {
        newTags.push(tag);
      }
    });

    return newTags;
  },

  @computed("category_id")
  get category() {
    return Category.findById(this.category_id);
  },

  @discourseComputed("reminder_at", "currentUser")
  formattedReminder(bookmarkReminderAt, currentUser) {
    return capitalize(
      formattedReminderTime(
        bookmarkReminderAt,
        currentUser.user_option.timezone
      )
    );
  },

  @discourseComputed("reminder_at")
  reminderAtExpired(bookmarkReminderAt) {
    return moment(bookmarkReminderAt) < moment();
  },

  @discourseComputed()
  topicForList() {
    // for topic level bookmarks we want to jump to the last unread post URL,
    // which the topic-link helper does by default if no linked post number is
    // provided
    const linkedPostNumber =
      this.bookmarkable_type === "Topic" ? null : this.linked_post_number;

    return Topic.create({
      id: this.topic_id,
      fancy_title: this.fancy_title,
      linked_post_number: linkedPostNumber,
      last_read_post_number: this.last_read_post_number,
      highest_post_number: this.highest_post_number,
    });
  },

  @discourseComputed("bookmarkable_type")
  bookmarkableTopicAlike(bookmarkable_type) {
    return ["Topic", "Post"].includes(bookmarkable_type);
  },
});

Bookmark.reopenClass({
  create(args) {
    args = args || {};
    args.currentUser = args.currentUser || User.current();
    args.user = User.create(args.user);
    return this._super(args);
  },

  createFor(user, bookmarkableType, bookmarkableId) {
    return Bookmark.create({
      bookmarkable_type: bookmarkableType,
      bookmarkable_id: bookmarkableId,
      user_id: user.id,
      auto_delete_preference: user.user_option.bookmark_auto_delete_preference,
    });
  },

  async applyTransformations(bookmarks) {
    await applyModelTransformations("bookmark", bookmarks);
  },
});

export default Bookmark;
