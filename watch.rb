require "nokogiri"
require "httparty"
require "logger"
require "dotenv"

# load environment variables
Dotenv.load

current_date = Time.now.strftime("%Y-%m-%d-%H:%M:%S")

@logger = Logger.new("logs/#{current_date}.log")
@logger.level = Logger::INFO

puts "Logging output to logs/#{current_date}.log"

@domain = "jamesg.blog"

headers = {
    "User-Agent" => "link-rot-detector (https://github.com/capjamesg/markdown-html-link-rot)"
}

@substitutions = []
@failed_substitutions = []

directories_to_include = [
    "_posts",
    "_likes",
    "_watches",
    "_bookmarks",
    "_reposts",
    "templates"
]

def get_archive_link(anchor)
    if !anchor.start_with?("http")
        is_site_link = true
        anchor = "https://#{@domain}/#{anchor.rstrip}"
    else
        is_site_link = false
    end

    begin
        r = HTTParty.get(anchor, headers: @headers)
        # don't run archive substitution on valid urls
        if r.code != 404
            return nil, nil
        end
    rescue StandardError => e
        puts e
        logger.warn("Failed to get archive link for #{anchor}")
        logger.warn(e)
        nil
    end

    if is_site_link == true
        @failed_substitutions << anchor
        return nil, nil
    end

    archive_link = "https://archive.org/wayback/available?url=#{anchor}"

    begin
        req = HTTParty.get(archive_link)
    rescue
        @failed_substitutions << anchor
        return nil, nil
    end

    if req.code != 200
        @logger.info("Error: #{anchor} could not be retrieved from the Wayback Machine")

        return nil, nil
    end

    as_json = JSON.parse(req.body)

    if as_json["archived_snapshots"] == {}
        @logger.info("Error: #{anchor} could not be retrieved from the Wayback Machine")

        return nil, nil
    end

    closest_link = as_json["archived_snapshots"]["closest"]["url"]
    
    @logger.info("#{anchor} -> #{closest_link}")

    return anchor, closest_link
end

markdown_files = Dir.glob("**/*.md") + Dir.glob("**/*.html")

for f in markdown_files
    if !directories_to_include.include?(File.dirname(f))
        next
    end

    changed = false

    page = File.open(f)

    full_page = page.read

    markdown_links = full_page.scan(/\[(.*?)\]\((.*?)\)/)

    @logger.info("Processing #{f}")

    for l in markdown_links
        anchor = l[1]

        anchor, closest_link = get_archive_link(anchor)

        if anchor == nil || closest_link == nil
            next
        end

        # replace old link with new one
        # add (archived) message to indicate a link has been archived
        @substitutions << [anchor, closest_link]

        puts "Substituting #{anchor} with #{closest_link}"
        
        full_page.gsub!("(#{anchor})", "(#{closest_link}) (archived)")

        changed = true
    end

    # get link path and anchor text
    html_links = full_page.scan(/<a.*?href="(.*?)".*?>(.*?)<\/a>/)

    for l in html_links
        anchor = l[0]

        anchor, closest_link = get_archive_link(anchor)

        if anchor == nil || closest_link == nil
            next
        end

        # replace old link with new one
        # add (archived) message to indicate a link has been archived
        @substitutions << [anchor, closest_link]

        puts closest_link
        
        # replace regex link with archive link
        full_page.gsub!(/<a.*?href="(.*?)".*?>(.*?)<\/a>/, "<a href=\"#{closest_link}\">\\2</a> (archived)")

        changed = true
    end

    if changed == true
        File.open(f, "w") do |file|
            puts "Fixed a link on #{f}"
            file.write full_page
        end
    end
end

to_send = """
Cali has identified #{@substitutions.length} broken links. These links have been replaced with archived versions.

See below for the changes made.

#{@substitutions.map { |s| "* #{s[0]} -> #{s[1]}" }.join("\n")}
"""

if @failed_substitutions.length > 0
    to_send += "\n\nThe following links could not be archived:\n\n"
    to_send += @failed_substitutions.map { |s| "* #{s}" }.join("\n")
end

# get args
args = ARGV

if args.length > 1 && args[0] == "--webhook"
    headers = {
        "Authorization" => "Basic #{ENV["CALI_API_KEY"]}"
    }

    message = {
        "message" => to_send
    }

    req = HTTParty.post("https://cali.jamesg.blog", body: message, headers: headers)

    if req.code == 200
        puts "Result sent to Cali"
    else
        puts "Error: #{req.code}"
    end
else
    puts to_send
end