/*
 * Copyright 2026 AkitaOnRails
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.Imap.ClientServiceTest : TestCase {


    public ClientServiceTest() {
        base("Geary.Imap.ClientServiceTest");
        add_test("disconnect_handler_lifecycle", disconnect_handler_lifecycle);
    }

    public void disconnect_handler_lifecycle() throws GLib.Error {
        var account = new Geary.AccountInformation(
            "test",
            Geary.ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new Geary.RFC822.MailboxAddress(null, "test@example.com")
        );
        var endpoint = new Geary.Endpoint(
            new GLib.NetworkAddress("localhost", 143),
            Geary.TlsNegotiationMethod.NONE,
            0
        );
        var service = new ClientService(
            account,
            account.incoming,
            endpoint
        );
        var session = new ClientSession(endpoint, new Quirks());

        service.track_session_disconnect(session);
        assert_true(service.is_tracking_session_disconnect(session));

        service.untrack_session_disconnect(session);
        assert_false(service.is_tracking_session_disconnect(session));
    }

}
