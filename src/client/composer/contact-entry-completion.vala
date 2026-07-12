/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class ContactEntryCompletion : Gtk.EntryCompletion, Geary.BaseInterface {


    // Minimum visibility for the contact to appear in autocompletion.
    private const Geary.Contact.Importance VISIBILITY_THRESHOLD =
        Geary.Contact.Importance.SEEN;

    // Maximum number of suggestions to display.
    private const int SEARCH_LIMIT = 20;


    public enum Column {
        CONTACT,
        MAILBOX;

        public static Type[] get_types() {
            return {
                typeof(Application.Contact), // CONTACT
                typeof(Geary.RFC822.MailboxAddress) // MAILBOX
            };
        }
    }


    // Stores to search, in priority order. The first is the sender's
    // account; suggestions are drawn from all accounts and
    // de-duplicated by address.
    private Gee.List<Application.ContactStore> contact_stores;

    // Text between the start of the entry or of the previous email
    // address and the current position of the cursor, if any.
    private string current_key = "";

    // List of (possibly incomplete) email addresses in the entry.
    private Gee.ArrayList<string> address_parts = new Gee.ArrayList<string>();

    // Index of the email address the cursor is currently at
    private int cursor_at_address = 0;

    private GLib.Cancellable? search_cancellable = null;
    private Gtk.TreeIter? last_iter = null;

    // GtkEntryCompletion's popup is a positioned toplevel that some
    // Wayland compositors (e.g. wlroots-based) never map, so
    // suggestions are shown in a GtkPopover instead, which is a
    // proper xdg_popup. See on_entry_key_press for its keyboard
    // handling.
    private Gtk.Popover? suggestion_popover = null;
    private Gtk.ListBox? suggestion_list = null;
    private int visible_matches = 0;
    private int selected_index = -1;


    public ContactEntryCompletion(
        Gee.Collection<Application.ContactStore> contact_stores
    ) {
        base_ref();
        this.contact_stores =
            new Gee.ArrayList<Application.ContactStore>();
        this.contact_stores.add_all(contact_stores);
        this.model = new_model();
        this.popup_completion = false;

        // Always match all rows, since the model will only contain
        // matching addresses from the search query
        set_match_func(() => true);

        Gtk.CellRendererPixbuf icon_renderer = new Gtk.CellRendererPixbuf();
        icon_renderer.xpad = 2;
        icon_renderer.ypad = 2;
        pack_start(icon_renderer, false);
        set_cell_data_func(icon_renderer, cell_icon_data);

        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
        icon_renderer.ypad = 2;
        pack_start(text_renderer, true);
        set_cell_data_func(text_renderer, cell_text_data);

        // cursor-on-match isn't fired unless this is true
        this.inline_selection = true;

        this.match_selected.connect(on_match_selected);
        this.cursor_on_match.connect(on_cursor_on_match);
    }

    ~ContactEntryCompletion() {
        base_unref();
    }

    public void update_model() {
        this.last_iter = null;

        update_addresses();

        if (this.search_cancellable != null) {
            this.search_cancellable.cancel();
            this.search_cancellable = null;
        }

        Gtk.ListStore model = (Gtk.ListStore) this.model;
        string completion_key = this.current_key;
        if (!Geary.String.is_empty_or_whitespace(completion_key)) {
            this.search_cancellable = new GLib.Cancellable();
            this.search_contacts.begin(completion_key, this.search_cancellable);
        } else {
            model.clear();
            hide_suggestions();
        }
    }

    public void trigger_selection() {
        if (accept_selected_suggestion()) {
            return;
        }
        if (this.last_iter != null) {
            insert_address_at_cursor(this.last_iter);
            this.last_iter = null;
        }
    }

    internal static bool is_completion_visible(int highest_importance) {
        return highest_importance >= VISIBILITY_THRESHOLD;
    }

    internal static int next_suggestion_index(int current, int count) {
        return (count <= 0) ? -1 : (current + 1) % count;
    }

    internal static int previous_suggestion_index(int current, int count) {
        if (count <= 0) {
            return -1;
        }
        return (current <= 0) ? count - 1 : current - 1;
    }

    internal static bool is_completion_address(string email) {
        string[] parts = email.split("@", 2);
        if (parts.length != 2) {
            return true;
        }

        string local_part = parts[0].normalize().casefold();
        string compact = local_part.replace("-", "");
        compact = compact.replace("_", "");
        compact = compact.replace(".", "");
        return compact != "noreply" && compact != "donotreply";
    }

    private void update_addresses() {
        Gtk.Entry? entry = get_entry() as Gtk.Entry;
        if (entry != null) {
            this.current_key = "";
            this.cursor_at_address = 0;
            this.address_parts.clear();

            // NB: Do not strip any white space from the addresses,
            // otherwise we won't be able to accurately insert
            // addresses in the middle of the list in
            // ::insert_address_at_cursor.

            string text = entry.get_text();
            int cursor_pos = entry.get_position();

            int current_char = 0;
            unichar c = 0;
            int start_idx = 0;
            int next_idx = 0;
            bool in_quote = false;
            while (text.get_next_char(ref next_idx, out c)) {
                if (current_char == cursor_pos &&
                    current_char != 0) {
                    if (c != ',' ) {
                        // Strip whitespace here though so it does not
                        // interfere with search and highlighting.
                        this.current_key = text.slice(
                            start_idx, next_idx
                        ).strip();
                    }
                    // We're in the middle of the address, so it
                    // hasn't yet been added to the list and hence we
                    // don't need to subtract 1 from its size here
                    this.cursor_at_address = this.address_parts.size;
                }

                switch (c) {
                case ',':
                    if (!in_quote) {
                        // Don't include the comma in the address
                        string address = text.slice(start_idx, next_idx - 1);
                        this.address_parts.add(address);
                        // Don't include it in the next one, either
                        start_idx = next_idx;
                    }
                    break;

                case '"':
                    in_quote = !in_quote;
                    break;
                }

                current_char++;
            }

            // Add any remaining text after the last comma
            string address = text.substring(start_idx);
            this.address_parts.add(address);
        }
    }

    private void insert_address_at_cursor(Gtk.TreeIter iter) {
        Gtk.Entry? entry = get_entry() as Gtk.Entry;
        if (entry != null) {

            // Take care to do a delete then an insert here so that
            // Component.EntryUndo can combine the two into a single
            // undoable command.

            int start_char = 0;
            if (this.cursor_at_address > 0) {
                start_char = this.address_parts.slice(
                    0, this.cursor_at_address
                ).fold<int>(
                    // Address parts don't contain commas, so need to add
                    // an char width for it. Don't need to worry about
                    // spaces because they are preserved by
                    // ::update_addresses.
                    (a, chars) => a.char_count() + chars + 1, 0
                );
            }
            int end_char = entry.get_position();

            // Format and use the selected address
            GLib.Value value;
            this.model.get_value(iter, Column.MAILBOX, out value);
            Geary.RFC822.MailboxAddress mailbox =
                (Geary.RFC822.MailboxAddress) value.get_object();
            string formatted = mailbox.to_full_display();
            if (this.cursor_at_address != 0) {
                // Isn't the first address, so add some whitespace to
                // pad it out
                formatted = " " + formatted;
            }
            if (entry.get_position() < entry.buffer.get_length() &&
                this.address_parts[this.cursor_at_address].strip() !=
                this.current_key.strip()) {
                // Isn't at the end of the entry, and the address
                // under the cursor does not simply consist of the
                // lookup key (i.e. is effectively already empty
                // otherwise), so add a comma to separate this address
                // from the next one
                formatted = formatted + ", ";
            }
            this.address_parts.insert(this.cursor_at_address, formatted);

            // Update the entry text
            if (start_char < end_char) {
                entry.delete_text(start_char, end_char);
            }
            entry.insert_text(formatted, -1, ref start_char);

            // Update the entry cursor position. The previous call
            // updates the start so just use that, but add extra space
            // for the comma and any white space at the start of the
            // next address.
            if (start_char < entry.buffer.get_length()) {
                start_char += 2;
            }
            entry.set_position(start_char);
        }
    }

    private async void search_contacts(string query,
                                       GLib.Cancellable? cancellable) {
        Gee.List<Application.Contact> results =
            new Gee.ArrayList<Application.Contact>();
        try {
            foreach (Application.ContactStore contacts
                     in this.contact_stores) {
                results.add_all(
                    yield contacts.search(
                        query,
                        VISIBILITY_THRESHOLD,
                        SEARCH_LIMIT,
                        cancellable
                    )
                );
                if (results.size >= SEARCH_LIMIT) {
                    break;
                }
            }
        } catch (GLib.IOError.CANCELLED err) {
            // All good
        } catch (GLib.Error err) {
            debug("Error searching contacts for completion: %s", err.message);
        }

        if (!cancellable.is_cancelled()) {
            Gtk.ListStore model = new_model();
            Gee.Set<string> seen = new Gee.HashSet<string>();
            int rows = 0;
            foreach (Application.Contact contact in results) {
                if (rows >= SEARCH_LIMIT) {
                    break;
                }
                foreach (Geary.RFC822.MailboxAddress addr
                          in contact.email_addresses) {
                    if (is_completion_address(addr.address) &&
                        seen.add(addr.address.normalize().casefold())) {
                        Gtk.TreeIter iter;
                        model.append(out iter);
                        model.set(iter, Column.CONTACT, contact);
                        model.set(iter, Column.MAILBOX, addr);
                        rows++;
                        if (rows >= SEARCH_LIMIT) {
                            break;
                        }
                    }
                }
            }
            this.model = model;
            show_suggestions();
        }
    }

    private void ensure_popover() {
        if (this.suggestion_popover != null) {
            return;
        }
        Gtk.Entry? entry = get_entry() as Gtk.Entry;
        if (entry == null) {
            return;
        }

        Gtk.Popover popover = new Gtk.Popover(entry);
        popover.position = Gtk.PositionType.BOTTOM;
        popover.modal = false;
        popover.can_focus = false;

        Gtk.ListBox list = new Gtk.ListBox();
        list.can_focus = false;
        list.selection_mode = Gtk.SelectionMode.SINGLE;
        list.row_activated.connect(on_suggestion_row_activated);
        popover.add(list);

        this.suggestion_popover = popover;
        this.suggestion_list = list;

        entry.key_press_event.connect(on_entry_key_press);
        entry.focus_out_event.connect(() => {
                hide_suggestions();
                return Gdk.EVENT_PROPAGATE;
            });
    }

    private void show_suggestions() {
        ensure_popover();
        Gtk.Entry? entry = get_entry() as Gtk.Entry;
        if (this.suggestion_popover == null || entry == null) {
            return;
        }

        foreach (Gtk.Widget child in this.suggestion_list.get_children()) {
            child.destroy();
        }

        int rows = 0;
        Gtk.TreeIter iter;
        bool valid = this.model.get_iter_first(out iter);
        while (valid) {
            GLib.Value value;
            this.model.get_value(iter, Column.MAILBOX, out value);
            Geary.RFC822.MailboxAddress? addr =
                value.get_object() as Geary.RFC822.MailboxAddress;
            if (addr != null) {
                Gtk.Label label = new Gtk.Label(null);
                label.set_markup(match_prefix_contact(addr));
                label.can_focus = false;
                label.xalign = 0.0f;
                label.ellipsize = Pango.EllipsizeMode.END;
                label.margin_start = 8;
                label.margin_end = 8;
                label.margin_top = 4;
                label.margin_bottom = 4;

                Gtk.ListBoxRow row = new Gtk.ListBoxRow();
                row.can_focus = false;
                row.add(label);
                this.suggestion_list.add(row);
                rows++;
            }
            valid = this.model.iter_next(ref iter);
        }

        this.visible_matches = rows;
        // Only pop up in response to the user actually typing,
        // never when the entry is filled programmatically.
        if (rows > 0 && entry.is_focus) {
            this.selected_index = 0;
            this.suggestion_list.select_row(
                this.suggestion_list.get_row_at_index(0)
            );
            int cursor = entry.get_position();
            this.suggestion_popover.show_all();
            entry.grab_focus();
            entry.set_position(cursor);
        } else {
            hide_suggestions();
        }
    }

    private void hide_suggestions() {
        if (this.suggestion_popover != null) {
            this.suggestion_popover.hide();
        }
        this.visible_matches = 0;
        this.selected_index = -1;
    }

    private bool suggestions_visible() {
        return (
            this.suggestion_popover != null &&
            this.suggestion_popover.get_visible() &&
            this.visible_matches > 0
        );
    }

    private bool accept_selected_suggestion() {
        bool accepted = false;
        if (suggestions_visible()) {
            int index = int.max(this.selected_index, 0);
            Gtk.TreeIter iter;
            if (this.model.get_iter_from_string(out iter, index.to_string())) {
                insert_address_at_cursor(iter);
                accepted = true;
            }
            hide_suggestions();
        }
        return accepted;
    }

    private void select_suggestion(int index) {
        this.selected_index = index;
        this.suggestion_list.select_row(
            this.suggestion_list.get_row_at_index(index)
        );
    }

    private void on_suggestion_row_activated(Gtk.ListBoxRow row) {
        this.selected_index = row.get_index();
        accept_selected_suggestion();
    }

    private bool on_entry_key_press(Gtk.Widget widget, Gdk.EventKey event) {
        if (!suggestions_visible()) {
            return Gdk.EVENT_PROPAGATE;
        }
        switch (event.keyval) {
        case Gdk.Key.Escape:
            hide_suggestions();
            return Gdk.EVENT_STOP;

        case Gdk.Key.Return:
        case Gdk.Key.KP_Enter:
            accept_selected_suggestion();
            return Gdk.EVENT_STOP;

        case Gdk.Key.Down:
            select_suggestion(
                next_suggestion_index(
                    this.selected_index, this.visible_matches
                )
            );
            return Gdk.EVENT_STOP;

        case Gdk.Key.Up:
            select_suggestion(
                previous_suggestion_index(
                    this.selected_index, this.visible_matches
                )
            );
            return Gdk.EVENT_STOP;

        default:
            return Gdk.EVENT_PROPAGATE;
        }
    }

    private string match_prefix_contact(Geary.RFC822.MailboxAddress mailbox) {
        string email = match_prefix_string(mailbox.address);
        if (mailbox.name != null && !mailbox.is_spoofed()) {
            string real_name = match_prefix_string(mailbox.name);
            // email and real_name were already escaped, then <b></b> tags
            // were added to highlight matches. We don't want to escape
            // them again.
            email = (
                real_name +
                Markup.escape_text(" <") + email + Markup.escape_text(">")
            );
        }
        return email;
    }

    private string? match_prefix_string(string haystack) {
        string value = haystack;
        if (!Geary.String.is_empty(this.current_key)) {
            bool matched = false;
            try {
                string escaped_needle = Regex.escape_string(
                    this.current_key.normalize()
                );
                Regex regex = new Regex(
                    "\\b" + escaped_needle,
                    RegexCompileFlags.CASELESS
                );
                string haystack_normalized = haystack.normalize();
                if (regex.match(haystack_normalized)) {
                    value = regex.replace_eval(
                        haystack_normalized, -1, 0, 0, eval_callback
                    );
                    matched = true;
                }
            } catch (RegexError err) {
                debug("Error matching regex: %s", err.message);
            }

            value = Markup.escape_text(value)
                .replace("&#x91;", "<b>")
                .replace("&#x92;", "</b>");
        }

        return value;
    }

    private bool eval_callback(GLib.MatchInfo match_info,
                               GLib.StringBuilder result) {
        string? match = match_info.fetch(0);
        if (match != null) {
            result.append("\xc2\x91%s\xc2\x92".printf(match));
            // This is UTF-8 encoding of U+0091 and U+0092
        }
        return false;
    }

    private void cell_icon_data(Gtk.CellLayout cell_layout,
                                Gtk.CellRenderer cell,
                                Gtk.TreeModel tree_model,
                                Gtk.TreeIter iter) {
        GLib.Value value;
        tree_model.get_value(iter, Column.CONTACT, out value);
        Application.Contact? contact = value.get_object() as Application.Contact;

        string icon = "";
        if (contact != null) {
            if (contact.is_favourite) {
                icon = "starred-symbolic";
            } else if (contact.is_desktop_contact) {
                icon = "avatar-default-symbolic";
            }
        }

        Gtk.CellRendererPixbuf renderer = (Gtk.CellRendererPixbuf) cell;
        renderer.icon_name = icon;
    }

    private void cell_text_data(Gtk.CellLayout cell_layout,
                                Gtk.CellRenderer cell,
                                Gtk.TreeModel tree_model,
                                Gtk.TreeIter iter) {
        GLib.Value value;
        tree_model.get_value(iter, Column.MAILBOX, out value);
        Geary.RFC822.MailboxAddress? mailbox =
            value.get_object() as Geary.RFC822.MailboxAddress;

        string markup = "";
        if (mailbox != null) {
            markup = this.match_prefix_contact(mailbox);
        }

        Gtk.CellRendererText renderer = (Gtk.CellRendererText) cell;
        renderer.markup = markup;
    }

    private inline Gtk.ListStore new_model() {
        return new Gtk.ListStore.newv(Column.get_types());
    }

    private bool on_match_selected(Gtk.TreeModel model, Gtk.TreeIter iter) {
        insert_address_at_cursor(iter);
        return true;
    }

    private bool on_cursor_on_match(Gtk.TreeModel model, Gtk.TreeIter iter) {
        this.last_iter = iter;
        return true;
    }

}
