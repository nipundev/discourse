import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { schedule } from "@ember/runloop";
import { inject as service } from "@ember/service";
import DButton from "discourse/components/d-button";
import ConfirmSession from "discourse/components/dialog-messages/confirm-session";
import PasskeyOptionsDropdown from "discourse/components/user-preferences/passkey-options-dropdown";
import RenamePasskey from "discourse/components/user-preferences/rename-passkey";
import formatDate from "discourse/helpers/format-date";
import { popupAjaxError } from "discourse/lib/ajax-error";
import {
  bufferToBase64,
  stringToBuffer,
  WebauthnAbortHandler,
} from "discourse/lib/webauthn";
import I18n from "discourse-i18n";

export default class UserPasskeys extends Component {
  @service dialog;
  @service currentUser;
  @service capabilities;
  @service router;

  instructions = I18n.t("user.passkeys.short_description");
  title = I18n.t("user.passkeys.title");
  addedPrefix = I18n.t("user.passkeys.added_prefix");
  lastUsedPrefix = I18n.t("user.passkeys.last_used_prefix");
  neverUsed = I18n.t("user.passkeys.never_used");

  get showActions() {
    return (
      this.currentUser.id === this.args.model.id &&
      !this.capabilities.isAppWebview
    );
  }

  async createPasskey() {
    try {
      const response = await this.args.model.createPasskey();

      const publicKeyCredentialCreationOptions = {
        challenge: Uint8Array.from(response.challenge, (c) => c.charCodeAt(0)),
        rp: {
          name: response.rp_name,
          id: response.rp_id,
        },
        user: {
          id: Uint8Array.from(response.user_secure_id, (c) => c.charCodeAt(0)),
          name: this.currentUser.username,
          displayName: this.currentUser.username,
        },
        pubKeyCredParams: response.supported_algorithms.map((alg) => {
          return { type: "public-key", alg };
        }),
        excludeCredentials: response.existing_passkey_credential_ids.map(
          (credentialId) => {
            return {
              type: "public-key",
              id: stringToBuffer(atob(credentialId)),
            };
          }
        ),
        authenticatorSelection: {
          // https://www.w3.org/TR/webauthn-2/#user-verification
          // for passkeys (first factor), user verification should be marked as required
          // it ensures browser prompts user for PIN/fingerprint/faceID before authenticating
          userVerification: "required",
          // See https://w3c.github.io/webauthn/#sctn-createCredential for context
          // This ensures that the authenticator stores a client-side private key
          // physical security keys (like Yubikey) need this
          requireResidentKey: true,
        },
      };

      const credential = await navigator.credentials.create({
        publicKey: publicKeyCredentialCreationOptions,
        signal: WebauthnAbortHandler.signal(),
      });

      let credentialParam = {
        id: credential.id,
        rawId: bufferToBase64(credential.rawId),
        type: credential.type,
        attestation: bufferToBase64(credential.response.attestationObject),
        clientData: bufferToBase64(credential.response.clientDataJSON),
        name: I18n.t("user.passkeys.name.default"),
      };

      const registrationResponse = await this.args.model.registerPasskey(
        credentialParam
      );

      if (registrationResponse.error) {
        this.dialog.alert(registrationResponse.error);
        return;
      }

      this.router.refresh();

      // Prompt to rename key after creating
      this.dialog.dialog({
        title: I18n.t("user.passkeys.passkey_successfully_created"),
        type: "notice",
        bodyComponent: RenamePasskey,
        bodyComponentModel: registrationResponse,
      });
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error(error);
      this.errorMessage =
        error.name === "InvalidStateError"
          ? I18n.t("user.passkeys.already_added_error")
          : I18n.t("user.passkeys.not_allowed_error");
      this.dialog.alert(this.errorMessage);
    }
  }

  confirmDelete(id) {
    schedule("afterRender", () => {
      this.dialog.deleteConfirm({
        title: I18n.t("user.passkeys.confirm_delete_passkey"),
        didConfirm: () => {
          this.args.model.deletePasskey(id).then(() => {
            this.router.refresh();
          });
        },
      });
    });
  }

  @action
  async addPasskey() {
    try {
      const trustedSession = await this.args.model.trustedSession();

      if (!trustedSession.success) {
        this.dialog.dialog({
          title: I18n.t("user.confirm_access.title"),
          type: "notice",
          bodyComponent: ConfirmSession,
          didConfirm: () => this.createPasskey(),
        });
      } else {
        await this.createPasskey();
      }
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  async deletePasskey(id) {
    try {
      const trustedSession = await this.args.model.trustedSession();

      if (!trustedSession.success) {
        this.dialog.dialog({
          title: I18n.t("user.confirm_access.title"),
          type: "notice",
          bodyComponent: ConfirmSession,
          didConfirm: () => this.confirmDelete(id),
        });
      } else {
        this.confirmDelete(id);
      }
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  renamePasskey(id, name) {
    this.dialog.dialog({
      title: I18n.t("user.passkeys.rename_passkey"),
      type: "notice",
      bodyComponent: RenamePasskey,
      bodyComponentModel: { id, name },
    });
  }

  <template>
    <div class="control-group pref-passkeys">
      <label class="control-label">
        {{this.title}}
      </label>
      <div class="instructions">
        {{this.instructions}}
      </div>

      <div class="pref-passkeys__rows">
        {{#each @model.user_passkeys as |passkey|}}
          <div class="row">
            <div class="passkey-left">
              <div class="row-passkey__name">{{passkey.name}}</div>
              <div class="row-passkey__created-date">
                <span class="prefix">
                  {{this.addedPrefix}}
                </span>
                {{formatDate
                  passkey.created_at
                  format="medium"
                  leaveAgo="true"
                }}
              </div>
              <div class="row-passkey__used-date">
                {{#if passkey.last_used}}
                  <span class="prefix">
                    {{this.lastUsedPrefix}}
                  </span>
                  {{formatDate
                    passkey.last_used
                    format="medium"
                    leaveAgo="true"
                  }}
                {{else}}
                  {{this.neverUsed}}
                {{/if}}
              </div>
            </div>
            {{#if this.showActions}}
              <div class="passkey-right">
                <div class="actions">
                  <PasskeyOptionsDropdown
                    @deletePasskey={{fn this.deletePasskey passkey.id}}
                    @renamePasskey={{fn
                      this.renamePasskey
                      passkey.id
                      passkey.name
                    }}
                  />
                </div>
              </div>
            {{/if}}
          </div>
        {{/each}}
      </div>

      {{#if this.showActions}}
        <div class="controls pref-passkeys__add">
          <DButton
            @action={{this.addPasskey}}
            @icon="plus"
            @label="user.passkeys.add_passkey"
          />
        </div>
      {{/if}}
    </div>
  </template>
}
