import Component from "@ember/component";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import DismissReadModal from "discourse/components/modal/dismiss-read";
import discourseComputed from "discourse-common/utils/decorators";
import I18n from "discourse-i18n";

export default Component.extend({
  tagName: "",
  classNames: ["topic-dismiss-buttons"],

  currentUser: service(),
  modal: service(),

  position: null,
  selectedTopics: null,
  model: null,

  @discourseComputed("position")
  containerClass(position) {
    return `dismiss-container-${position}`;
  },

  @discourseComputed("position")
  dismissReadId(position) {
    return `dismiss-topics-${position}`;
  },

  @discourseComputed("position")
  dismissNewId(position) {
    return `dismiss-new-${position}`;
  },

  @discourseComputed("position", "model.topics.length")
  showBasedOnPosition(position, topicCount) {
    if (position !== "top") {
      return true;
    }

    return this.currentUser?.new_new_view_enabled || topicCount > 5;
  },

  @discourseComputed("selectedTopics.length")
  dismissLabel(selectedTopicCount) {
    if (selectedTopicCount === 0) {
      return I18n.t("topics.bulk.dismiss_button");
    }
    return I18n.t("topics.bulk.dismiss_button_with_selected", {
      count: selectedTopicCount,
    });
  },

  @discourseComputed("selectedTopics.length")
  dismissNewLabel(selectedTopicCount) {
    if (this.currentUser?.new_new_view_enabled) {
      return I18n.t("topics.bulk.dismiss_button");
    } else if (selectedTopicCount === 0) {
      return I18n.t("topics.bulk.dismiss_new");
    }
    return I18n.t("topics.bulk.dismiss_new_with_selected", {
      count: selectedTopicCount,
    });
  },

  @action
  dismissReadPosts() {
    let dismissTitle = "topics.bulk.dismiss_read";
    if (this.selectedTopics.length) {
      dismissTitle = "topics.bulk.dismiss_read_with_selected";
    }
    this.modal.show(DismissReadModal, {
      model: {
        title: dismissTitle,
        count: this.selectedTopics.length,
        dismissRead: this.dismissRead,
      },
    });
  },
});
