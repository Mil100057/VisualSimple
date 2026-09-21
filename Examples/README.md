# Test files for the structure checker

Each `error-*` file holds a single fault that VisualSimple must report in the status bar, with the faulty spot underlined. `correct.json` must show "Valid JSON".

- error-trailing-comma.json: trailing comma in the array, line 4.
- error-missing-comma.json: comma missing between two keys, line 3.
- error-duplicate-key.yaml: key `name` defined twice, line 8.
- error-indentation.yaml: indentation back to a level that does not exist, line 4.
- error-colon.yaml: `:` inside an unquoted value, line 2.
- error-tag.html: span never closed before the div, line 11.
- error-attribute.html: unclosed quote in href, line 4.
- error-columns.csv: two fields instead of three, line 3.
- error-xml.xml: item opened, config closed, line 4.
- error-brace.js: brace of the for loop never closed, reported at the end of the file, line 7.
- error-brace.swift: brace of the struct never closed, line 1.
- error-duplicate-key.toml: key `host` defined twice in [server], line 4.
- error-duplicate.env: variable API_KEY defined twice, line 3.
- error-section.ini: section `[display` never closed, line 3.
- error-markdown.md: unclosed wikilink on line 3 (reported first), then an unclosed code block.
- error-strings.strings: semicolon missing after "bye", line 4 (reported before the duplicate "hello").
- error-plist.plist: two consecutive `<key>` elements, reported on line 7.
- error-sql.sql: unclosed parenthesis, line 3.

For the PDF editor, the hexadecimal view and the SVG preview, any file of those types will do.
