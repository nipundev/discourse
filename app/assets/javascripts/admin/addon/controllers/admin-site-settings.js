import Controller from "@ember/controller";
import { action } from "@ember/object";
import { alias } from "@ember/object/computed";
import { inject as service } from "@ember/service";
import { isEmpty } from "@ember/utils";
import { observes } from "@ember-decorators/object";
import { INPUT_DELAY } from "discourse-common/config/environment";
import { debounce } from "discourse-common/utils/decorators";
import I18n from "discourse-i18n";

export default class AdminSiteSettingsController extends Controller {
  @service router;

  filter = "";

  @alias("model") allSiteSettings;

  visibleSiteSettings = null;
  onlyOverridden = false;

  get maxResults() {
    return 100;
  }

  sortSettings(settings) {
    // Sort the site settings so that fuzzy results are at the bottom
    // and ordered by their gap count asc.
    return settings.sort((a, b) => {
      const aWeight = a.weight === undefined ? 0 : a.weight;
      const bWeight = b.weight === undefined ? 0 : b.weight;
      return aWeight - bWeight;
    });
  }

  performSearch(filter, allSiteSettings, onlyOverridden) {
    let pluginFilter;

    if (filter) {
      filter = filter
        .toLowerCase()
        .split(" ")
        .filter((word) => {
          if (word.length === 0) {
            return false;
          }

          if (word.startsWith("plugin:")) {
            pluginFilter = word.slice("plugin:".length).trim();
            return false;
          }

          return true;
        })
        .join(" ")
        .trim();
    }

    const all = {
      nameKey: "all_results",
      name: I18n.t("admin.site_settings.categories.all_results"),
      siteSettings: [],
    };

    const matchesGroupedByCategory = [all];
    const matches = [];

    const strippedQuery = filter.replace(/[^a-z0-9]/gi, "");
    let fuzzyRegex;
    let fuzzyRegexGaps;

    if (strippedQuery.length > 2) {
      fuzzyRegex = new RegExp(strippedQuery.split("").join(".*"), "i");
      fuzzyRegexGaps = new RegExp(strippedQuery.split("").join("(.*)"), "i");
    }

    allSiteSettings.forEach((settingsCategory) => {
      let fuzzyMatches = [];

      const siteSettings = settingsCategory.siteSettings.filter((item) => {
        if (onlyOverridden && !item.get("overridden")) {
          return false;
        }
        if (pluginFilter && item.plugin !== pluginFilter) {
          return false;
        }
        if (filter) {
          const setting = item.get("setting").toLowerCase();
          let filterResult =
            setting.includes(filter) ||
            setting.replace(/_/g, " ").includes(filter) ||
            item.get("description").toLowerCase().includes(filter) ||
            (item.get("keywords") || "")
              .replace(/_/g, " ")
              .toLowerCase()
              .includes(filter.replace(/_/g, " ")) ||
            (item.get("value") || "").toString().toLowerCase().includes(filter);
          if (!filterResult && fuzzyRegex && fuzzyRegex.test(setting)) {
            // Tightens up fuzzy search results a bit.
            const fuzzySearchLimiter = 25;
            const strippedSetting = setting.replace(/[^a-z0-9]/gi, "");
            if (
              strippedSetting.length <=
              strippedQuery.length + fuzzySearchLimiter
            ) {
              const gapResult = strippedSetting.match(fuzzyRegexGaps);
              if (gapResult) {
                item.weight = gapResult.filter((gap) => gap !== "").length;
              }
              fuzzyMatches.push(item);
            }
          }
          return filterResult;
        } else {
          return true;
        }
      });

      if (fuzzyMatches.length > 0) {
        siteSettings.pushObjects(fuzzyMatches);
      }

      if (siteSettings.length > 0) {
        matches.pushObjects(siteSettings);
        matchesGroupedByCategory.pushObject({
          nameKey: settingsCategory.nameKey,
          name: I18n.t(
            "admin.site_settings.categories." + settingsCategory.nameKey
          ),
          siteSettings: this.sortSettings(siteSettings),
          count: siteSettings.length,
        });
      }
    });

    all.siteSettings.pushObjects(matches.slice(0, this.maxResults));
    all.siteSettings = this.sortSettings(all.siteSettings);

    all.hasMore = matches.length > this.maxResults;
    all.count = all.hasMore ? `${this.maxResults}+` : matches.length;
    all.maxResults = this.maxResults;

    return matchesGroupedByCategory;
  }

  filterContentNow(category) {
    if (isEmpty(this.allSiteSettings)) {
      return;
    }

    if (isEmpty(this.filter) && !this.onlyOverridden) {
      this.set("visibleSiteSettings", this.allSiteSettings);
      if (this.categoryNameKey === "all_results") {
        this.router.transitionTo("adminSiteSettings");
      }
      return;
    }

    const matchesGroupedByCategory = this.performSearch(
      this.filter,
      this.allSiteSettings,
      this.onlyOverridden
    );

    const categoryMatches = matchesGroupedByCategory.findBy(
      "nameKey",
      category
    );

    if (!categoryMatches || categoryMatches.count === 0) {
      category = "all_results";
    }

    this.set("visibleSiteSettings", matchesGroupedByCategory);
    this.router.transitionTo(
      "adminSiteSettingsCategory",
      category || "all_results"
    );
  }

  @observes("filter", "onlyOverridden", "model")
  optsChanged() {
    this.filterContent();
  }

  @debounce(INPUT_DELAY)
  filterContent() {
    if (this._skipBounce) {
      this.set("_skipBounce", false);
    } else {
      if (!this.isDestroyed) {
        this.filterContentNow(this.categoryNameKey);
      }
    }
  }

  @action
  clearFilter() {
    this.setProperties({ filter: "", onlyOverridden: false });
  }

  @action
  toggleMenu() {
    const adminDetail = document.querySelector(".admin-detail");
    ["mobile-closed", "mobile-open"].forEach((state) => {
      adminDetail.classList.toggle(state);
    });
  }
}
