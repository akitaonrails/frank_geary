int main(string[] args) {
    assert(ContactAutocompletePolicy.is_importance_visible(60, 30));
    assert(ContactAutocompletePolicy.is_importance_visible(30, 30));
    assert(!ContactAutocompletePolicy.is_importance_visible(20, 30));

    assert(!ContactAutocompletePolicy.is_auto_generated_address("person@example.com"));
    assert(!ContactAutocompletePolicy.is_auto_generated_address("noreply"));
    assert(!ContactAutocompletePolicy.is_auto_generated_address("reply@example.com"));

    assert(ContactAutocompletePolicy.is_auto_generated_address("no-reply@example.com"));
    assert(ContactAutocompletePolicy.is_auto_generated_address("noreply@example.com"));
    assert(ContactAutocompletePolicy.is_auto_generated_address("do-not-reply@example.com"));
    assert(ContactAutocompletePolicy.is_auto_generated_address("donotreply@example.com"));
    assert(ContactAutocompletePolicy.is_auto_generated_address("do_not_reply@example.com"));
    assert(ContactAutocompletePolicy.is_auto_generated_address("do.not.reply@example.com"));

    // Keep the filter conservative: do not suppress domains or display names.
    assert(!ContactAutocompletePolicy.is_auto_generated_address("support@no-reply.example.com"));

    return 0;
}
