require "rubygems"
require "active_support/core_ext/hash"
require "active_support/inflector"
require "fileutils"
require "json"


# Constants
# ---------

ROOT = %x`git rev-parse --show-toplevel`.chomp
SOT_DIR = File.join ROOT, "gen", "tmp", "sot"
OUT_DIR = File.join ROOT, "gen", "tmp", "out"

ATTRIBUTES_TO_REMOVE = %w(
  class
  clip-path
  display
  height
  version
  width
  x
  xml:space
  xmlns
  xmlns:xlink
  y
)



# Functions
# ---------


def append_to_file(path_to_file, content)
  FileUtils.mkdir_p File.dirname(path_to_file)
  File.open(path_to_file, "a") { |f| f << content }
end


def confirm_icon(family, icon)
  svg = icon_svg(family, icon)

  unless svg.start_with?("<svg") or svg.start_with?("<?xml")
    puts "Download failed for `#{icon["name"]}`, wait a bit whilst I reset."
    sleep 5
    download_icon(family, icon, true)
  end
end


def download_icon(family, icon, override = false)
  filepath = icon_file_path(family, icon)

  if !File.exist?(filepath) || override
    FileUtils.mkdir_p File.dirname(filepath)
    IO.write filepath, %x`curl #{icon_url(family, icon)}`
  end
end


def escape(s)
  s.gsub(/ /, '\ ')
end


def escape_quotes(s)
  s.gsub('"', '\"')
end


def icon_file_path(family, icon)
  "#{SOT_DIR}/icons/#{family}/v#{icon["version"]}-#{icon["name"]}.svg"
end


def icon_function_name(name)
  case name
  when "360" ; "three_sixty"
  when "3d_rotation" ; "three_d_rotation"
  when "4k" ; "four_k"
  when "5g" ; "five_g"
  when "6_ft_apart" ; "six_ft_apart"
  else
    if name[0] =~ /\d/
      raise "An icon can't have a number as the first character (icon: `#{name}`)"
    else
      name
    end
  end
end


def icon_svg(family, icon)
  filepath = icon_file_path(family, icon)

  filepath
    .yield_self { |a| IO.read(a) }
    .yield_self { |a| a.gsub(/<\?xml[^\>]+>\n/m, "") }
    .yield_self { |a| a.gsub(/<\!--[^\>]+>\n/m, "") }
    .yield_self { |a| a.gsub(/<defs.*<\/defs>/m, "") }
    .yield_self { |a| a.gsub(/<clipPath.*<\/clipPath>/m, "") }
    .yield_self { |a| ATTRIBUTES_TO_REMOVE.reduce(a) {
      |b, attr| b.gsub(/\ #{attr}="[^"]*"/, " ")
    }}
end


def icon_url(family_normal, icon)
  family = family_normal.downcase.gsub(" ", "")
  name = icon["name"]
  version = icon["version"]

  "https://fonts.gstatic.com/s/i/#{family}/#{name}/v#{version}/24px.svg?download=true"
end



# Setup
# =====

# Clean up directories
FileUtils.rm_rf SOT_DIR
FileUtils.mkdir_p "#{SOT_DIR}/icons"

FileUtils.rm_rf OUT_DIR
FileUtils.mkdir_p OUT_DIR

# Download source of truth
%x`curl -o #{escape(SOT_DIR)}/icons.json https://fonts.google.com/metadata/icons`



# Generate
# ========

INDEX =
  "#{SOT_DIR}/icons.json"
    .yield_self { |a| IO.read(a) }
    .yield_self { |a| a.delete_prefix(")]}'\n") }
    .yield_self { |a| JSON.parse(a) }

ICONS =
  INDEX["icons"]

CATEGORIES = ICONS.reduce({}) do |memo, icon|
  cat = icon["categories"][0] || ""

  memo[cat] ||= { "name" => cat, "icons" => [] }
  memo[cat]["icons"].push(icon)

  memo
end.sort_by { |key, _| key }


def generate(family)
  module_name = family
    .gsub("Material Icons", "Material.Icons")
    .sub(" ", ".")
    .gsub(" ", "")

  dir_name = family
    .gsub("Material Icons", "Material/Icons")
    .sub(" ", "/")
    .gsub(" ", "")

  out_path = "#{OUT_DIR}/#{dir_name}.elm"
  filtered_icons = ICONS.reject { |i| i["unsupported_families"].include?(family) }
  filtered_icons_names = filtered_icons.map { |i| i["name"] }

  # {log}
  puts "Processing #{family}"

  # Header
  exposed = filtered_icons_names.map do |icon_name|
    icon_function_name icon_name
  end.join(", ")

  append_to_file out_path, <<~HERE
  module #{module_name} exposing (#{exposed})

  {-|
  HERE

  # Docs
  CATEGORIES.each do |_, cat|
    cat_name = cat["name"].humanize
    functions_names = cat["icons"]
      .sort_by { |icon| icon["name"] }
      .map do |icon|
        if filtered_icons_names.include? icon["name"]
          icon_function_name icon["name"]
        else
          nil
        end
      end
      .compact
      .join ", "

    append_to_file out_path, <<~HERE

    # #{cat_name}

    @docs #{functions_names}

    HERE
  end

  # Imports
  append_to_file out_path, <<~HERE
  -}

  import Material.Icons.Types exposing (Coloring, Icon)
  import Material.Icons.Internal exposing (icon)
  import Svg exposing (Svg, circle, g, path, polygon, polyline, rect, use, svg)
  import Svg.Attributes as A exposing (baseProfile, clipRule, cx, cy, d, enableBackground, fill, fillOpacity, fillRule, id, overflow, points, r, viewBox, x1, x2, xlinkHref, y1, y2)


  o : String -> Svg.Attribute msg
  o = A.opacity

  t : String -> Svg.Attribute msg
  t = A.transform
  HERE

  # Process each icon
  filtered_icons.each do |icon|
    icon_fn_name = icon_function_name icon["name"]

    puts "Processing #{family}/#{icon_fn_name}"

    download_icon(family, icon)
    confirm_icon(family, icon)

    svg             = icon_svg(family, icon)
    elm_icon_code   = %x`./node_modules/.bin/html-elm "#{escape_quotes(svg)}"`
                        .yield_self { |a| a.gsub(/^svg/, "icon") }
                        .yield_self { |a| a.gsub("baseprofile", "baseProfile") }
                        .yield_self { |a| a.gsub("clip-rule", "clipRule") }
                        .yield_self { |a| a.gsub("clippath", "Svg.clipPath") }
                        .yield_self { |a| a.gsub("enable-background", "enableBackground") }
                        .yield_self { |a| a.gsub("fill-opacity", "fillOpacity") }
                        .yield_self { |a| a.gsub("fill-rule", "fillRule") }
                        .yield_self { |a| a.gsub("opacity \"", "o \"") }
                        .yield_self { |a| a.gsub("transform \"", "t \"") }
                        .yield_self { |a| a.gsub("viewbox", "viewBox") }
                        .yield_self { |a| a.gsub("xlink:href", "xlinkHref") }
                        .yield_self { |a| a.gsub(/\n/, "\n    ") }
                        .strip

    append_to_file out_path, <<~HERE


      {-|-}
      #{icon_fn_name} : Icon msg
      #{icon_fn_name} =
          #{elm_icon_code}
    HERE
  end

end


INDEX["families"].each do |family|
  generate(family)
end



# Move
# ====

%x`mv #{escape(ROOT)}/src/Material/Icons/Types.elm #{escape(ROOT)}/src/Types.elm`
%x`mv #{escape(ROOT)}/src/Material/Icons/Internal.elm #{escape(ROOT)}/src/Internal.elm`

%x`rm -rf #{escape(ROOT)}/src/Material`
%x`mv -f #{escape(OUT_DIR)}/* #{escape(ROOT)}/src`
%x`rm -rf #{escape(OUT_DIR)}`

%x`mv #{escape(ROOT)}/src/Types.elm #{escape(ROOT)}/src/Material/Icons/Types.elm`
%x`mv #{escape(ROOT)}/src/Internal.elm #{escape(ROOT)}/src/Material/Icons/Internal.elm`



# elm-format
# ==========

%x`(cd ..; elm-format #{escape(ROOT)}/src --yes)`
