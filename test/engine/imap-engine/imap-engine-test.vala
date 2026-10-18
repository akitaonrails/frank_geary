/*
 * Copyright 2026 AkitaOnRails
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.ImapEngine.Test : TestCase {


    public Test() {
        base("Geary.ImapEngine.Test");
        add_test("remote_sync_retry_budget", remote_sync_retry_budget);
    }

    public void remote_sync_retry_budget() throws GLib.Error {
        int attempts_remaining = 3;
        GLib.Error transient = new GLib.IOError.TIMED_OUT("Timed out");

        assert_true(should_retry_remote_sync(transient, ref attempts_remaining));
        assert(attempts_remaining == 2);
        assert_true(should_retry_remote_sync(transient, ref attempts_remaining));
        assert(attempts_remaining == 1);
        assert_false(should_retry_remote_sync(transient, ref attempts_remaining));
        assert(attempts_remaining == 0);

        attempts_remaining = 3;
        GLib.Error permanent = new GLib.IOError.INVALID_ARGUMENT("Invalid");
        assert_false(should_retry_remote_sync(permanent, ref attempts_remaining));
        assert(attempts_remaining == 2);
    }

}
