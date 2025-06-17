require 'optparse'
require 'FileUtils'
require 'json'

class GooglePhotosFixer 

  METADATA_JSON = "supplemental-metadata.json"
  SUPPORTED_IMAGE_EXT = %w(.jpg .jpeg .png .gif .webp .heic .mov .mp4 .3gp .avi .mkv .webm)

  attr_reader :options, :fixes, :errors, :takeout_dir

  def initialize(takeout_dir)
    @takeout_dir = takeout_dir
    reset!
  end

  def reset!
    @fixes = []
    @errors = []
  end

  def debug(something)
    return unless $DEBUG

    Array(something).each do |item|
      puts "[DEBUG] #{item}"
    end
  end

  def filename(fullpath_filename)
    File.basename(fullpath_filename)
  end

  def filename_without_ext(filename)
    File.basename(filename).gsub(File.extname(filename), '')
  end

  def copy_file(origin, destination)
    if $COMMIT
      FileUtils.cp(origin, destination)
    else
      debug("cp #{origin} #{destination}")
    end
    fixes << "#{filename(origin)} copied to #{filename(destination)}"
  end

  def move_file(origin, destination)
    if $COMMIT
      FileUtils.mv(origin, destination)
    else
      debug("mv #{origin} #{destination}")
    end
    fixes << "#{filename(origin)} moved to #{filename(destination)}"
  rescue Exception => ex
    debug("ERROR #{ex.message}")
  end

  def delete_file(origin)
    if $COMMIT
      FileUtils.rm(origin)
    else
      debug("rm #{origin}")
    end
  end

  def write_file(name, content)
    if $COMMIT
      File.open(name, 'w') do |f|
        f.write(content)
      end
    else
      debug("#{name} << #{content}")
    end
    fixes << "#{filename(name)} written"
  end

  # Returns the default expected metadata filename
  # image_file: 20210529_155539.jpg
  # return: 20210529_155539.jpg.supplemental-metadata.json
  def metadata_file_for(image_file)
    "#{image_file}.#{METADATA_JSON}"
  end

  # Try detect the timestamp from file name pattern
  def infer_time_from_image_file(image_file)
    # for 20210529_155539 patterns
    filename = filename_without_ext(image_file)
    tokens = filename.scan(/(\d{4})(\d{2})(\d{2})\_(\d{2})(\d{2})(\d{2})/).flatten
    if tokens.compact == 6
      time = Time.new(*tokens)
      debug("Time inferred file: #{filename}, time: #{time}")
      return time
    end

    # for CameraZOOM-20131224200623261 patterns
    # for CameraZOOM-2013 12 24 20 06 23 261 patterns
    tokens = filename.scan(/(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{3})/).flatten
    if tokens.compact == 7
      time = Time.new(*tokens)
      debug("Time inferred file: #{filename}, time: #{time}")
      return time
    end

    # for DJI_20250308180700_0070_D patterns
    tokens = filename.scan(/\_(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\_/).flatten
    if tokens.compact == 6
      time = Time.new(*tokens)
      debug("Time inferred file: #{filename}, time: #{time}")
      return time
    end

    # for Photos from 2024/P01020304.jpg or 2024/IMG_123123.jpg pattern
    tokens = image_file.scan(/Photos\ from\ (\d{4})\//).flatten
    if tokens.compact == 1
      time = Time.new(*tokens)
      debug("Time inferred file: #{image_file}, time: #{time}")
      return time
    end

    return nil
  end

  # Fallback to generate a metadata filename based on filename pattern
  # image file: 20210529_155539.jpg
  # generated metadata: 20210529_155539.jpg.supplemental-metadata.json
  # time on metadata: 2021-05-29 15:55:39
  def generate_metadata_for_image_file(image_file)
    metadata_filename = metadata_file_for(image_file)
    return if File.exist?(metadata_filename)

    filename = filename_without_ext(image_file)
    if time = infer_time_from_image_file(image_file)
      json_content = {
        "title" => filename(image_file),
        "description": "Metadata inferred from #{filename}",
        "imageViews": "1",
        "creationTime": {
          "timestamp": time.to_i.to_s,
          "formatted": time.to_s
        },
        "photoTakenTime": {
          "timestamp": time.to_i.to_s,
          "formatted": time.to_s
        }
      }
      write_file(metadata_filename, content.to_json)
    else
      errors << "Unable to infer metadata for #{image_file}"
    end
  end

  # normalize truncated json metadata filenames
  # original: e471949f-d0b7-4f22-be33-225f556a92a4.jpg.suppl.json
  # fixed: e471949f-d0b7-4f22-be33-225f556a92a4.jpg.supplemental-metadata.json
  def fix_divergent_metadata_filename(json_file)
    unless json_file.end_with?(METADATA_JSON)
      meta_ext, meta_filename, img_ext, img_file, others = json_file.split('.').reverse
      fixed_json_file = json_file.gsub("#{meta_filename}.#{meta_ext}", METADATA_JSON)
      move_file(json_file, fixed_json_file)
      json_file = fixed_json_file
    end

    json_file
  end

  # for cases like:
  # 20210529_155539.jpg
  # 20210529_155539(1).jpg
  # 20210529_155539-editada.jpg
  # 20210529_155539.jpg.supplemental-metadata.json
  # 20210529_155539.jpg.supplemental-metadata(1).json
  def fix_metadata_file_for_image(image_file)
    # Create a metadata json for image "-editada" version
    # image file: 20210529_155539-editada.jpg
    # metadata file: 20210529_155539-editada.jpg.supplemental-metadata.json
    if image_file.index("-editada")
      original_file = image_file.gsub("-editada", "")
      original_meta = "#{original_file}.#{METADATA_JSON}"

      if File.exist?(original_meta)
        edited_meta = "#{image_file}.#{METADATA_JSON}"
        copy_file(original_meta, edited_meta)
      end
    end

    # fix metadata filenames for sequencial images filenames
    # image file: 20210529_155539(1).jpg
    # wrong metadata: 20210529_155539.jpg.supplemental-metadata(1).json
    # fixed metadata: 20210529_155539(1).jpg.supplemental-metadata.json
    matched = filename_without_ext(image_file).match(/(?<num>\(\d+\)$)/)
    if matched
      num = matched[:num]
      filename_without_num = filename(image_file).gsub(num, "")
      dir = File.dirname(image_file)

      wrong_json_file = File.join(dir, "#{filename_without_num}.supplemental-metadata#{num}.json")
      fixed_json_file = File.join(dir, "#{filename(image_file)}.#{METADATA_JSON}")
      if File.exist?(wrong_json_file)
        if File.exist?(fixed_json_file)
          errors << "Metadata file already exist: #{fixed_json_file}"
        else
          move_file(wrong_json_file, fixed_json_file)
        end
      else
        errors << "Metadata file: #{wrong_json_file} not exist for image: #{image_file}"
      end
    end

    image_file
  end

  def remove_metadata_file(json_file)
    dirs = takeout_dir.split('/')
    dirs.pop

    metadata_dir = File.join(File.join(dirs), 'metadata', '/')
    unless Dir.exist?(metadata_dir)
      FileUtils.mkdir(metadata_dir)
    end

    target_file = json_file.gsub(takeout_dir, metadata_dir)
    target_dir = File.dirname(target_file)
    unless Dir.exist?(target_dir)
      FileUtils.mkdir_p(target_dir)
    end
    move_file(json_file, target_file)
    # copy_file(json_file, target_file)

    target_file
  end

  def execute(generate_metadata: false, clean_metadata: false)
    reset!

    all_files = Dir.glob(File.join(takeout_dir, "/**/*"))
    puts "Total files found on #{takeout_dir}: #{all_files.size}"

    years_files = all_files.select { |f| File.dirname(f).match?(/Photos\ from\ (\d+)$/) }
    puts "Total photos from YYYY dirs found: #{years_files.size}"
    puts years_files if $DEBUG

    image_files = years_files.select { |f| SUPPORTED_IMAGE_EXT.include?(File.extname(f).downcase) }
    puts "Total supported photos formats found: #{image_files.size}"
    debug(image_files)

    json_files = years_files.select { |f| File.extname(f).downcase == '.json' }
    puts "Total metadata files found: #{json_files.size}"
    debug(json_files)

    json_files = json_files.map do |json_file|
      fix_divergent_metadata_filename(json_file)
    end

    image_files = image_files.map do |image_file|
      fixed_metadata = fix_metadata_file_for_image(image_file)
      generate_metadata_for_image_file(image_file) if generate_metadata
      fixed_metadata
    end

    if errors.size > 0
      puts "\nProcess finalized with #{errors.size} errors:"
      errors.each_with_index do |error, index|
        puts "[#{index+1}/#{errors.size}] #{error}"
      end
    end

    if fixes.size > 0
      puts "\nProcess finalized with #{fixes.size} fixes:"
      fixes.each_with_index do |fix, index|
        puts "[#{index+1}/#{fixes.size}] #{fix}"
      end
    end

    not_found = image_files.select do |img|
      !File.exist?(metadata_file_for(img))
    end

    if not_found.size > 0
      puts "\nMetadata not found for #{not_found.size} files:"
      not_found.each_with_index do |file, index|
        puts "[#{index+1}/#{not_found.size}] #{file}"
      end
    end

    if clean_metadata
      moved_metadata_files = json_files.map do |json_file|
        remove_metadata_file(json_file)
      end
      puts "\nMetadata files was moved to other dir:"
      moved_metadata_files.each_with_index do |file, index|
        puts "[#{index+1}/#{moved_metadata_files.size}] #{file}"
      end
    end
  end
end

def run_tests
  def fixer
    GooglePhotosFixer.new("/tmp/")
  end

  def test(description, &block)
    result = block.call if block_given?
    puts "#{description}: #{result ? 'PASS' : 'FAIL'}"
  end

  test("fix wrong metadata filenames") do
    fixer.fix_divergent_metadata_filename("IMG_1234.jpg.suppl-met.json") == "IMG_1234.jpg.supplemental-metadata.json"
  end

  test("can't fix metadata filename for sequencial images") do
    fixer = GooglePhotosFixer.new("/tmp/")
    fixer.fix_metadata_file_for_image("IMG_1234(1).jpg")

    fixer.errors.last == "Metadata file: ./IMG_1234.jpg.supplemental-metadata(1).json not exist for image: IMG_1234(1).jpg"
  end

  test("fix metadata filename for sequencial images") do
    tmp_file = "/tmp/IMG_1234.jpg.supplemental-metadata(1).json"
    FileUtils.touch(tmp_file)

    fixer = GooglePhotosFixer.new("/tmp/")
    fixer.fix_metadata_file_for_image("/tmp/IMG_1234(1).jpg")
    FileUtils.rm(tmp_file)

    fixer.fixes.last == "IMG_1234.jpg.supplemental-metadata(1).json moved to IMG_1234(1).jpg.supplemental-metadata.json"
  end
end

usage_description = "Usage: ruby fixer.rb [options] path/to/takeout/dir/"
options = {}
option_parser = OptionParser.new do |opts|
  opts.banner = usage_description

  opts.on("-v", "--[no-]verbose", "Run verbosely (debug mode)") do |v|
    $DEBUG = v
  end

  opts.on("-s", "--save", "Efectivally fixes the photos [dry-run mode is the default]") do |v|
    $COMMIT = v
  end

  opts.on("-g", "--generate-metadata", "Try to generate metadata inferring the timestamp from file names") do |v|
    options[:generate_metadata] = v
  end

  opts.on("-c", "--clean-metadata", "Remove metadata files from photos dir (move to separated dir)") do |v|
    options[:clean_metadata] = v
  end

  opts.on("-m", "--metadata-dir", "Indicate the directory where metadata files are stored") do |v|
  end

  opts.on("-t", "--test", "Run unit tests") do |v|
    options[:test] = v
  end
end.parse!

if options[:test]
  run_tests
else
  takeout_dir = ARGV[0] || raise(usage_description)
  fixer = GooglePhotosFixer.new(takeout_dir)
  fixer.execute(**options)
end
