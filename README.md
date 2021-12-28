# Markdown / HTML Link Rot Detector

A Ruby script to detect link rot in HTML and markdown documents and replace broken links with an Internet Archive backup.

## Getting Started

First, install the required dependencies for this project to work using bundle:

    bundle install

Next, run the link rot detector program:

    ruby watch.rb

The link rot detector program will check for links that return 404s or an invalid response. If such a link is found, the Internet Archive's Wayback Machine API is queried to see if a snapshot of the site is available. If a snapshot is found, the link to the most recent snapshot is used to replace the broken link in the HTML / markdown document being read.

All changes are logged to a log file whose name is printed to the console when the program runs.

You can optionally use the --webhook flag to send a notification with a JSON payload to a server when the program has finished running. The payload looks like this:

{
    "message": "
        Cali has identified 0 broken links. These links have been replaced with archived versions.

        See below for the changes made.

        [List of broken links, if applicable]
    "
}

## Technologies

The following libraries and technologies are used in this project:

- Ruby
- nokogiri
- logger
- HTTParty

## Contributors

- capjamesg