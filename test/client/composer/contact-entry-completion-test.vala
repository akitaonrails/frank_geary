/*
 * Copyright 2026 FrankGeary contributors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Composer.ContactEntryCompletionTest : TestCase {


    public ContactEntryCompletionTest() {
        base("Composer.ContactEntryCompletionTest");
        add_test("completion_visibility", completion_visibility);
        add_test("completion_address_filter", completion_address_filter);
    }

    public void completion_visibility() throws Error {
        assert_true(ContactEntryCompletion.is_completion_visible(
            Geary.Contact.Importance.SENT_TO
        ));
        assert_true(ContactEntryCompletion.is_completion_visible(
            Geary.Contact.Importance.RECEIVED_FROM
        ));
        assert_true(ContactEntryCompletion.is_completion_visible(
            Geary.Contact.Importance.SEEN
        ));
        assert_false(ContactEntryCompletion.is_completion_visible(
            Geary.Contact.Importance.SEEN - 1
        ));
    }

    public void completion_address_filter() throws Error {
        assert_true(ContactEntryCompletion.is_completion_address(
            "person@example.com"
        ));
        assert_true(ContactEntryCompletion.is_completion_address(
            "noreply"
        ));
        assert_true(ContactEntryCompletion.is_completion_address(
            "reply@example.com"
        ));
        assert_true(ContactEntryCompletion.is_completion_address(
            "support@no-reply.example.com"
        ));

        assert_false(ContactEntryCompletion.is_completion_address(
            "no-reply@example.com"
        ));
        assert_false(ContactEntryCompletion.is_completion_address(
            "noreply@example.com"
        ));
        assert_false(ContactEntryCompletion.is_completion_address(
            "do-not-reply@example.com"
        ));
        assert_false(ContactEntryCompletion.is_completion_address(
            "donotreply@example.com"
        ));
        assert_false(ContactEntryCompletion.is_completion_address(
            "do_not_reply@example.com"
        ));
        assert_false(ContactEntryCompletion.is_completion_address(
            "do.not.reply@example.com"
        ));
    }

}
