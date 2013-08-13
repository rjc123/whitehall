require 'tmpdir'
require 'open3'

class BulkUpload
  extend ActiveModel::Naming
  include ActiveModel::Validations
  include ActiveModel::Conversion

  validate :attachments_are_valid?

  attr_reader :attachments

  def self.from_files(edition, file_paths)
    attachment_params = file_paths.map do |file|
      { attachment_data_attributes: { file: File.open(file) } }
    end

    new(edition, attachments: attachment_params)
  end

  def initialize(edition, params = {})
    @edition = edition
    @attachments = params.fetch(:attachments, []).map do |attachment_params|
      file = attachment_params.fetch(:attachment_data_attributes, {})[:file]
      attachment = if file
        scope = edition.attachments.with_filename(File.basename(file))
        scope.first_or_initialize(attachment_params)
      else
        Attachment.new(attachment_params)
      end
    end
  end

  def to_model
    self
  end

  def persisted?
    false
  end

  def save_attachments_to_edition
    if valid?
      @edition.attachments << attachments
    else
      false
    end
  end

  def attachments_are_valid?
    attachments.each { |attachment| attachment.valid? }
    unless attachments.all? { |attachment| attachment.valid? }
      errors[:base] << 'Please enter missing fields for each attachment'
    end
  end

  class ZipFile
    class << self
      attr_accessor :default_root_directory
    end

    extend  ActiveModel::Naming
    include ActiveModel::Validations
    include ActiveModel::Conversion

    attr_reader :zip_file, :temp_location

    validates :zip_file, presence: true
    validate :must_be_a_zip_file
    validate :contains_only_whitelisted_file_types

    def persisted?
      false
    end

    def initialize(zip_file=nil)
      @zip_file = zip_file
      store_temporarily
    end

    def temp_dir
      @temp_dir ||= Dir.mktmpdir(nil, BulkUpload::ZipFile.default_root_directory)
    end

    def store_temporarily
      return if @zip_file.nil?
      @temp_location = File.join(self.temp_dir, self.zip_file.original_filename)
      FileUtils.cp(self.zip_file.tempfile, @temp_location)
    end

    def extracted_file_paths
      if @extracted_files_paths.nil?
        lines = extract_contents.split(/[\r\n]+/).map { |line| line.strip }
        lines = lines
          .reject { |line| line =~ /\A(Archive|creating):/ }
          .reject { |line| line =~ /\/__MACOSX\// }
        files = lines.map { |f| f.gsub(/\A(inflating|extracting):\s+/, '') }
        @extracted_files_paths = files.map { |file| File.expand_path(file) }
      end
      @extracted_files_paths
    end

    def cleanup_extracted_files
      FileUtils.rmtree(temp_dir, secure: true)
    end

    def extract_contents
      unzip = Whitehall.system_binaries[:unzip]
      destination = File.join(self.temp_dir, 'extracted')
      @unzip_output ||= `#{unzip} -o -d #{destination} #{self.temp_location}`
    end

    def must_be_a_zip_file
      if @zip_file.present? && (! is_a_zip?)
        errors.add(:zip_file, 'not a zip file')
      end
    end

    def is_a_zip?
      zipinfo = Whitehall.system_binaries[:zipinfo]
      _, _, errs = Open3.popen3("#{zipinfo} -1 #{self.temp_location} > /dev/null")
      errs.read.empty?
    end

    private

    def contains_only_whitelisted_file_types
      if @zip_file.present? && is_a_zip? && contains_disallowed_file_types?
        errors.add(:zip_file, 'contains invalid files')
      end
    end

    def contains_disallowed_file_types?
      extracted_file_paths.any? do |path|
        extension = File.extname(path).sub(/^\./, '')
        ! AttachmentUploader::EXTENSION_WHITE_LIST.include?(extension)
      end
    end
  end
end
