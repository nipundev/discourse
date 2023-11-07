import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import { fixQuotes } from "discourse/components/post-text-selection";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { translateModKey } from "discourse/lib/utilities";
import autoFocus from "discourse/modifiers/auto-focus";
import I18n from "discourse-i18n";

export default class FastEdit extends Component {
  @tracked value = this.args.initialValue;
  @tracked isSaving = false;

  buttonTitle = I18n.t("composer.title", {
    modifier: translateModKey("Meta+"),
  });

  get disabled() {
    return this.value === this.args.initialValue;
  }

  @action
  onKeydown(event) {
    if (
      event.key === "Enter" &&
      (event.ctrlKey || event.metaKey) &&
      !this.disabled
    ) {
      this.save();
    }
  }

  @action
  updateValue(event) {
    event.preventDefault();
    this.value = event.target.value;
  }

  @action
  async save() {
    this.isSaving = true;

    try {
      const result = await ajax(`/posts/${this.args.post.id}`);
      const newRaw = result.raw.replace(
        fixQuotes(this.args.initialValue),
        fixQuotes(this.value)
      );

      await this.args.post.save({ raw: newRaw });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSaving = false;
      this.args.close();
    }
  }

  <template>
    {{! template-lint-disable no-pointer-down-event-binding }}
    {{! template-lint-disable no-invalid-interactive }}
    <div class="fast-edit-container" {{on "keydown" this.onKeydown}}>
      <textarea
        {{on "input" this.updateValue}}
        id="fast-edit-input"
        {{autoFocus}}
      >{{@initialValue}}</textarea>

      <DButton
        class="btn-small btn-primary save-fast-edit"
        @action={{this.save}}
        @icon="pencil-alt"
        @label="composer.save_edit"
        @translatedTitle={{this.buttonTitle}}
        @isLoading={{this.isSaving}}
        @disabled={{this.disabled}}
      />
    </div>
  </template>
}
