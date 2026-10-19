/*
 * Copyright 2026 AkitaOnRails
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.ImapEngine.Test : TestCase {


    private class RetryOperation : ReplayOperation {

        public RetryOperation() {
            base("RetryTest", REMOTE_ONLY, RETRY);
            this.max_remote_retries = 3;
        }

        public override bool is_remote_failure_recoverable(GLib.Error err) {
            return is_recoverable_flag_update_failure(err);
        }

        public override uint get_remote_retry_delay() {
            return get_flag_update_retry_delay(this.remote_retry_count);
        }

        public override string describe_state() {
            return "";
        }

    }


    public Test() {
        base("Geary.ImapEngine.Test");
        add_test("remote_sync_retry_budget", remote_sync_retry_budget);
        add_test("flag_update_retry_policy", flag_update_retry_policy);
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

    public void flag_update_retry_policy() throws GLib.Error {
        GLib.Error server_error = new Geary.ImapError.SERVER_ERROR(
            "System Error (Failure)"
        );
        GLib.Error invalid = new GLib.IOError.INVALID_ARGUMENT("Invalid");

        assert_true(is_recoverable_flag_update_failure(server_error));
        assert_false(is_recoverable_flag_update_failure(invalid));

        var operation = new RetryOperation();
        assert_true(operation.prepare_remote_retry(server_error));
        assert(operation.remote_retry_count == 1);
        assert(operation.get_remote_retry_delay() == 1);
        assert_true(operation.prepare_remote_retry(server_error));
        assert(operation.remote_retry_count == 2);
        assert(operation.get_remote_retry_delay() == 3);
        assert_true(operation.prepare_remote_retry(server_error));
        assert(operation.remote_retry_count == 3);
        assert(operation.get_remote_retry_delay() == 9);
        assert_false(operation.prepare_remote_retry(server_error));
        assert(operation.remote_retry_count == 3);

        var permanent_operation = new RetryOperation();
        assert_false(permanent_operation.prepare_remote_retry(invalid));
        assert(permanent_operation.remote_retry_count == 0);
    }

}
