#!/bin/sh
# Build Final_Report.docx and convert it to PDF.
# Usage: ./render.sh [pages.json]   (run pages.py after a render to refresh pages.json)
set -e
cd "$(dirname "$0")"
python3 build.py $1 >/dev/null
soffice --headless --convert-to pdf Final_Report.docx >/dev/null 2>&1
pdfinfo Final_Report.pdf | grep Pages
