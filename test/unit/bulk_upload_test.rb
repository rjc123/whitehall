require 'test_helper'

class BulkUploadTest < ActiveSupport::TestCase

  def fixture_file(filename)
    File.open(File.join(Rails.root, 'test', 'fixtures', filename))
  end

  def valid_attachment_params
    {
      attachments_attributes: {
        '0' => attributes_for(:attachment),
        '1' => attributes_for(:attachment)
      }
    }
  end

  def invalid_attachment_params
    valid_attachment_params.tap do |params|
      params[:attachments_attributes]['0'][:title] = ''
    end
  end

  test 'can be instantiated from an array of file paths' do
    files = [fixture_file('greenpaper.pdf'), fixture_file('whitepaper.pdf')]

    attachments = BulkUpload.from_files(create(:news_article), files)

    assert_equal 2, attachments.attachments.size
    assert_equal 'greenpaper.pdf', attachments.attachments[0].filename
    assert_equal 'whitepaper.pdf', attachments.attachments[1].filename
  end

  test '.new loads attachments from the edition if filenames match' do
    edition = create(:news_article, :with_attachment)
    existing_filename = edition.attachments.first.filename
    attachment_params = {
      attachments_attributes: {
        '0' => {
          title: 'New attachment',
          attachment_data_attributes: { file: fixture_file('whitepaper.pdf') }
        },
        '1' => {
          title: 'New title for existing attachment',
          attachment_data_attributes: { file: fixture_file(existing_filename) }
        }
      }
    }
    attachments = BulkUpload.new(edition, attachment_params).attachments
    assert attachments.first.new_record?, 'Attachment should be new record'
    refute attachments.last.new_record?, "Attachment shouldn't be new record"
  end

  test '.new replaces AttachmentData on each Attachment if file specified' do
    edition = create(:news_article, :with_attachment)
    existing_filename = edition.attachments.first.filename
    attachment_params = {
      attachments_attributes: {
        '0' => {
          attachment_data_attributes: { file: fixture_file(existing_filename) }
        }
      }
    }
    attachment = BulkUpload.new(edition, attachment_params).attachments.first
    assert attachment.attachment_data.new_record?, 'AttachmentData should be new record'
  end

  test '#save_attachments_to_edition saves attachments to the edition' do
    edition = create(:news_article)
    bulk_upload = BulkUpload.new(edition, valid_attachment_params)
    assert_difference('edition.attachments.count', 2) do
      assert bulk_upload.save_attachments_to_edition, 'should return true'
    end
  end
  
  test '#save_attachments_to_edition updates existing attachments' do
    edition = create(:news_article, :with_attachment)
    existing_filename = edition.attachments.first.filename
    new_title = 'New title for existing attachment'
    attachment_params = {
      attachments_attributes: {
        '0' => {
          title: new_title,
          attachment_data_attributes: { file: fixture_file(existing_filename) }
        }
      }
    }
    bulk_upload = BulkUpload.new(edition, attachment_params)
    bulk_upload.save_attachments_to_edition
    assert_equal 1, edition.attachments.length
    assert_equal new_title, edition.attachments.first.title
  end

  # test '#save_attachments_to_edition replaces existing files' do
    # skip 'copy setup from previous test, then refactor'
    # assert_not_nil edition.attachments.first.attachment_data
    # assert_not_equal existing_attachment_data, edition.attachments.first.attachment_data
    # existing_attachment_data = edition.attachments.first.attachment_data
  # end

  test '#save_attachments_to_edition does not save any attachments if one is invalid' do
    edition = create(:news_article)
    bulk_upload = BulkUpload.new(edition, invalid_attachment_params)
    assert_no_difference('edition.attachments.count') do
      refute bulk_upload.save_attachments_to_edition, 'should return false'
    end
  end

  test '#save_attachments_to_edition adds errors when attachments are invalid' do
    edition = create(:news_article)
    bulk_upload = BulkUpload.new(edition, invalid_attachment_params)
    bulk_upload.save_attachments_to_edition
    assert bulk_upload.errors[:base].any?
  end
end

class BulkUploadZipFileTest < ActiveSupport::TestCase
  test 'is invalid without a zip_file' do
    refute BulkUpload::ZipFile.new(nil).valid?
  end

  test 'is invalid if the zip file doesn\'t superficially look like a zip file' do
    refute BulkUpload::ZipFile.new(not_a_zip_file).valid?
  end

  test 'is invalid if the zip file superficially looks like a zip file, but isn\'t' do
    refute BulkUpload::ZipFile.new(superficial_zip_file).valid?
  end

  test 'is valid if the file is actually a zip' do
    assert BulkUpload::ZipFile.new(a_zip_file).valid?
  end

  test 'is invalid if the zip file contains illegal file types' do
    zip_file = BulkUpload::ZipFile.new(a_zip_file_with_dodgy_file_types)
    refute zip_file.valid?
    assert_match /contains invalid files/, zip_file.errors[:zip_file][0]
  end

  test 'extracted_file_paths returns extracted file paths' do
    zip_file = BulkUpload::ZipFile.new(a_zip_file)
    extracted = zip_file.extracted_file_paths
    assert_equal 2, extracted.size
    assert extracted.include?(File.join(zip_file.temp_dir, 'extracted', 'two-pages.pdf').to_s)
    assert extracted.include?(File.join(zip_file.temp_dir, 'extracted', 'greenpaper.pdf').to_s)
  end

  test 'cleanup_extracted_files deletes the files that were unzipped' do
    zip_file = BulkUpload::ZipFile.new(a_zip_file)
    extracted = zip_file.extracted_file_paths
    zip_file.cleanup_extracted_files
    assert extracted.none? { |path| File.exist?(path) }, 'files should be deleted'
    refute File.exist?(zip_file.temp_dir), 'temporary dir should be deleted'
  end

  test 'extracted_file_paths ignores OS X resource fork files' do
    zip_file = BulkUpload::ZipFile.new(zip_file_with_os_x_resource_fork)
    extracted = zip_file.extracted_file_paths
    assert_equal 1, extracted.size
    assert extracted.include?(File.join(zip_file.temp_dir, 'extracted', 'greenpaper.pdf').to_s)
  end

  def uploaded_file(fixture_filename)
    ActionDispatch::Http::UploadedFile.new(
      filename: fixture_filename,
      tempfile: File.open(Rails.root.join('test', 'fixtures', fixture_filename))
    )
  end

  def not_a_zip_file
    uploaded_file('greenpaper.pdf')
  end

  def superficial_zip_file
    ActionDispatch::Http::UploadedFile.new(
      filename: 'greenpaper-not-a-zip.zip',
      tempfile: File.open(Rails.root.join('test', 'fixtures', 'greenpaper.pdf'))
    )
  end

  def a_zip_file
    uploaded_file('two-pages-and-greenpaper.zip')
  end

  def zip_file_with_os_x_resource_fork
    uploaded_file('greenpaper-with-osx-resource-fork.zip')
  end

  def a_zip_file_with_dodgy_file_types
    uploaded_file('sample_attachment_containing_exe.zip')
  end
end
