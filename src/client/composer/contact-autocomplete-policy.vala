/* Copyright 2026 FrankGeary contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace ContactAutocompletePolicy {

public bool is_importance_visible(int highest_importance, int threshold) {
    return highest_importance >= threshold;
}

public bool is_auto_generated_local_part(string local_part) {
    string folded = local_part.normalize().casefold();
    string compact = folded.replace("-", "").replace("_", "").replace(".", "");
    return compact == "noreply" || compact == "donotreply";
}

public bool is_auto_generated_address(string email) {
    string[] parts = email.split("@", 2);
    return parts.length == 2 && is_auto_generated_local_part(parts[0]);
}

}
