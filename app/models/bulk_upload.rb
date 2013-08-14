require 'tmpdir'
require 'open3'

class BulkUpload
  extend ActiveModel::Naming
  include ActiveModel::Validations
  include ActiveModel::Conversion

  validate :attachments_are_valid?

  attr_reader :attachments

  def self.from_files(edition, file_paths)
    params = {}
    file_paths.each_with_index do |file, index|
      params[index.to_s] = { attachment_data_attributes: { file: File.open(file) } }
    end
    new(edition, attachments_attributes: params)
  end

  def initialize(edition, params)
    @edition = edition
    @attachments = initialize_attachments(params[:attachments_attributes])
  end

  def attachments_attributes=(stuff)
  end

  def to_model
    self
  end

  def persisted?
    false
  end

  def save_attachments_to_edition
    if valid?
      attachments.each do |attachment|
        if attachment.new_record?
          EditionAttachment.create!(edition: @edition, attachment: attachment)
        else
          attachment.save!
        end
      end
    else
      false
    end
  end

  def attachments_are_valid?
    attachments.each { |attachment| attachment.valid? }
    if attachments.all? { |attachment| attachment.valid? }
      true
    else
      errors[:base] << 'Please enter missing fields for each attachment'
      false
    end
  end

  private

  def mutable_attachment_with_file(basename)
    # The attachment is read only as it was found by the with_filename
    # scope, which uses `joins`, which marks everything it returns as
    # read only.
    read_only_instance = @edition.attachments.with_filename(basename).first
    Attachment.find(read_only_instance.id)
  end

  def existing_attachment_with_new_data(data_attributes)
    attachment = nil
    if file = data_attributes[:file]
      attachment = mutable_attachment_with_file(File.basename(file))
      if attachment
        data_attributes.merge!(to_replace_id: attachment.attachment_data.id)
        attachment.attachment_data = AttachmentData.new(data_attributes)
      end
    end
    attachment
  end

  def initialize_attachments(attachments_attributes_params)
    @attachments ||= attachments_attributes_params.map do |index, attachment_params|
      data_attributes = attachment_params.fetch(:attachment_data_attributes, {})
      attachment = existing_attachment_with_new_data(data_attributes)
      attachment || Attachment.new(attachment_params)
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
