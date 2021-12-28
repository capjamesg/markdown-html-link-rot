require "optparse"
require "ostruct"
require "nokogiri"
require "httparty"
require "logger"
require "dotenv"
require "thread"

# create threads list
# threading is used in this program to improve performance
# since so many network requests are made
threads = []

# load environment variables
Dotenv.load

current_date = Time.now.strftime("%Y-%m-%d-%H:%M:%S")

@logger = Logger.new("logs/#{current_date}.log")
@logger.level = Logger::INFO

# get dictionary of command ARG
options = {}

OptionParser.new do |option|
    option.on("-f", "--file FILE", "Directory to process") do |f| options[:file] = f end
    option.on("-d", "--domain DOMAIN", "Domain to use") do |d| options[:domain] = d end
    option.on("-h", "--help", "Show this message") do puts option; exit end
    option.on("-w", "--webhook", "Send webhook when link program has completed") do |w| options[:webhook] = w end
    option.on("-a", "--webhook-auth KEY", "Key to be sent in an Authorization header to Webhook") do |a| options[:key] = a end
    option.on("-e", "--include DIR", "Folders to process, separated by commas") do |e| options[:exclude] = e end
end.parse!

if !options.key?(:file)
    puts "Please specify a file to process."
    exit
end

if !options.key?(:domain)
    puts "Please specify a domain to use."
    exit
end

@domain = options[:domain]

puts "Welcome to the HTML / Markdown link rot substitution tool."
puts "This tool will take a file and replace all links to the site with links to the archive.org website."
puts "This program may take a while to run depending on how many outgoing links you have on your site."

puts "Logging output to logs/#{current_date}.log"

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

# add user specified directories to list of directories to include
if options.key?(:exclude)
    directories_to_include << options[:exclude].split(",")
end

def get_archive_link(anchor)
    if !anchor.start_with?("http")
        is_site_link = true
        
        if anchor.start_with?("/")
            anchor = "https://#{@domain}#{anchor.rstrip}"
        else
            return nil, nil
        end
    else
        is_site_link = false
    end

    begin
        r = HTTParty.get(anchor, headers: @headers, follow_redirects: true, timeout: 10)

        # don't run archive substitution on valid urls
        if r.code != 404
            return nil, nil
        end
    rescue StandardError => e
        @logger.warn("Failed to get archive link for #{anchor}")
        @logger.warn(e)
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
        @failed_substitutions << anchor

        return nil, nil
    end

    as_json = JSON.parse(req.body)

    if as_json["archived_snapshots"] == {}
        @logger.info("Error: #{anchor} could not be retrieved from the Wayback Machine")
        @failed_substitutions << anchor

        return nil, nil
    end

    closest_link = as_json["archived_snapshots"]["closest"]["url"]
    
    @logger.info("#{anchor} -> #{closest_link}")

    return anchor, closest_link
end

markdown_files = Dir.glob("**/*.md") + Dir.glob("**/*.html")

markdown_files.each do |f|
    threads << Thread.new {
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
    }
end

# execute all threads
threads.each { |thr| thr.join }

if @substitutions.length > 0
    to_send = """
    The link rot bot has identified #{@substitutions.length} broken links. These links have been replaced with archived versions.

    See below for the changes made.

    #{@substitutions.map { |s| "* #{s[0]} -> #{s[1]}" }.join("\n")}
    """
else
    to_send = "The link rot bot has identified no broken links."
end

if @failed_substitutions.length > 0
    to_send += "\n\n#{@failed_substitutions.length} links could not be archived. These are:\n\n"
    to_send += @failed_substitutions.map { |s| "* #{s}" }.join("\n")
end

if options[:webhook] != nil
    headers = {
        "Authorization" => "Basic #{options[:key]}"
    }

    message = {
        "message" => to_send
    }

    req = HTTParty.post(options[:webhook], body: message, headers: headers)

    if req.code == 200
        puts "Result sent to webhook"
    else
        puts "Error: #{req.code}"
    end
else
    puts to_send
end