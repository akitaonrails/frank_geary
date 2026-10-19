/*
 * Copyright 2026 AkitaOnRails
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Components.ProblemReportInfoBarTest : TestCase {


    public ProblemReportInfoBarTest() {
        base("Components.ProblemReportInfoBarTest");
        add_test("outbox_rejection", outbox_rejection);
        add_test("retried_flag_update", retried_flag_update);
    }

    public void outbox_rejection() throws GLib.Error {
        var account = new Geary.AccountInformation(
            "test",
            Geary.ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new Geary.RFC822.MailboxAddress(null, "test@example.com")
        );
        var report = new Geary.OutboxProblemReport(
            account,
            new Geary.SmtpError.MESSAGE_REJECTED("Rejected")
        );
        var test_article = new ProblemReportInfoBar(report);

        assert(test_article.status.label == "Email not sent");
        assert(
            test_article.description.label ==
            "A message in the Outbox for test@example.com was rejected by the mail server."
        );
        assert_true(test_article.show_close_button);
        assert(test_article.get_action_area().get_children().length() == 1);
    }

    public void retried_flag_update() throws GLib.Error {
        var account = new Geary.AccountInformation(
            "test",
            Geary.ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new Geary.RFC822.MailboxAddress(null, "test@example.com")
        );
        var report = new Geary.AccountProblemReport(
            account,
            new Geary.ImapError.RETRY_EXHAUSTED(
                "Flag update failed after 3 retries"
            )
        );
        var test_article = new ProblemReportInfoBar(report);

        assert(test_article.status.label == "Account problem");
        assert(
            test_article.description.label ==
            "The mail server repeatedly rejected a message status change for " +
            "test@example.com. It may not have been saved on the server."
        );
        assert_true(test_article.show_close_button);
        assert(test_article.get_action_area().get_children().length() == 1);
    }

}
