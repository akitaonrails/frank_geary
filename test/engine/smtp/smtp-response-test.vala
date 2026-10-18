/*
 * Copyright 2026 AkitaOnRails
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.Smtp.ResponseTest : TestCase {


    public ResponseTest() {
        base("Geary.Smtp.ResponseTest");
        add_test("message_rejected", message_rejected);
        add_test("server_error", server_error);
    }

    public void message_rejected() throws GLib.Error {
        Response response = new_response();
        try {
            response.throw_message_rejected("Unable to send message");
            assert_not_reached();
        } catch (SmtpError.MESSAGE_REJECTED err) {
            assert(
                err.message ==
                "Unable to send message: 552-First line\n552 Second line"
            );
        }
    }

    public void server_error() throws GLib.Error {
        Response response = new_response();
        try {
            response.throw_error("Server error");
            assert_not_reached();
        } catch (SmtpError.SERVER_ERROR err) {
            assert(err.message == "Server error: 552-First line\n552 Second line");
        }
    }

    private Response new_response() throws GLib.Error {
        var lines = new Gee.ArrayList<ResponseLine>();
        lines.add(ResponseLine.deserialize("552-First line"));
        lines.add(ResponseLine.deserialize("552 Second line"));
        return new Response(lines);
    }

}
