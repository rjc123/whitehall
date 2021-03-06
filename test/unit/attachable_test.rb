require 'test_helper'

class AttachableTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess

  test "allows attachment" do
    assert build(:publication).allows_attachments?
  end

  test "should allow multiple attachments" do
    attachment_1 = create(:file_attachment)
    attachment_2 = create(:file_attachment)

    publication = create(:publication, :with_file_attachment, attachments: [attachment_1, attachment_2])

    assert_equal [attachment_1, attachment_2], publication.attachments
  end

  test "should be able to add multiple attachments at once" do
    page = create(:supporting_page)

    file_attrs = attributes_for(:file_attachment)
    file_attrs.delete(:ordering)
    html_attrs = attributes_for(:html_attachment)
    html_attrs.delete(:ordering)

    page.attachments_attributes = [file_attrs, html_attrs]
    page.save!
    page.reload

    assert_equal 2, page.attachments.count
  end

  test "new attachments are put to the end of the list" do
    attachment_1 = create(:file_attachment, ordering: 0)
    attachment_2 = create(:file_attachment, ordering: 1)
    publication = create(:publication, :with_file_attachment, attachments: [attachment_1, attachment_2])

    attachment_3 = build(:file_attachment)
    publication.attachments << attachment_3

    assert_equal [attachment_1, attachment_2, attachment_3], publication.attachments(true)
  end

  test "should be invalid if an edition has an attachment but no alternative format provider" do
    attachment = build(:file_attachment)
    publication = build(:publication, attachments: [attachment], alternative_format_provider: nil)
    refute publication.valid?
  end

  test "should be invalid if an edition has an attachment but alternative format provider has no email address set" do
    attachment = build(:file_attachment)
    organisation = build(:organisation, alternative_format_contact_email: nil)
    publication = build(:publication, attachments: [attachment], alternative_format_provider: organisation)
    refute publication.valid?
  end

  test "should be invalid if an edition has an attachment but not yet passed virus scanning" do
    attachment = build(:file_attachment)
    attachment.stubs(:virus_status).returns :infected
    publication = create(:publication, :with_alternative_format_provider, attachments: [attachment])
    publication.skip_virus_status_check = false
    assert publication.valid?
    user = create(:departmental_editor)
    publication.change_note = "change-note"
    assert_raise(ActiveRecord::RecordInvalid, "Validation failed: Attachments must have passed virus scanning") { force_publish(publication) }
    refute publication.published?
  end

  test "should be valid without alternative format provider if no attachments" do
    publication = build(:publication, attachments: [])
    assert publication.valid?
  end

  test "should allow deletion of attachments via nested attributes" do
    attachment_1 = create(:file_attachment)
    attachment_2 = create(:file_attachment)

    publication = create(:publication, :with_file_attachment, attachments: [attachment_1, attachment_2])

    attributes = {
      attachment_1.id => attachment_1.attributes.merge('_destroy' => '1'),
      attachment_2.id => attachment_2.attributes.merge('_destroy' => '0'),
    }
    publication.update_attributes(attachments_attributes: attributes)
    publication.reload

    assert_equal [attachment_2], publication.attachments
  end

  test 'should say a edition does not have a thumbnail when it has no attachments' do
    edition = create(:publication)
    refute edition.has_thumbnail?
  end

  test 'should say a edition does not have a thumbnail when it has no thumbnailable attachments' do
    sample_csv = build(:file_attachment, file: fixture_file_upload('sample-from-excel.csv', 'text/csv'))

    edition = build(:publication)
    edition.attachments << sample_csv

    refute edition.has_thumbnail?
  end

  def build_edition_with_three_attachments
    @sample_csv = create(:file_attachment, file: fixture_file_upload('sample-from-excel.csv', 'text/csv'))
    @greenpaper_pdf = create(:file_attachment, file: fixture_file_upload('greenpaper.pdf', 'application/pdf'))
    @two_pages_pdf = create(:file_attachment, file: fixture_file_upload('two-pages.pdf'))

    edition = create(:publication)
    edition.attachments << @sample_csv
    edition.attachments << @greenpaper_pdf
    edition.attachments << @two_pages_pdf

    edition
  end

  test 'should say an edition has a thumbnail when it has a thumbnailable attachment' do
    edition = build_edition_with_three_attachments

    assert edition.has_thumbnail?
  end

  test 'should return the URL of a thumbnail when the edition has a thumbnailable attachment' do
    edition = build_edition_with_three_attachments

    assert_equal @greenpaper_pdf.url(:thumbnail), edition.thumbnail_url
  end

  test 'should include attachment content into the #search_index' do
    test_pdf = fixture_file_upload('simple.pdf', 'application/pdf')
    attachment = create(:file_attachment, file: test_pdf, title: "The title of the attachment",
      hoc_paper_number: "1234", parliamentary_session: '2013-14', command_paper_number: "Cm. 1234",
      unique_reference: "w123", isbn: "0140620222"
    )
    attachment.stubs(:extracted_text).returns "\nThis is a test pdf.\n\n\n"
    edition = create(:publication)
    edition.attachments << attachment

    index = edition.attachments.to_a.index { |attachment| attachment.kind_of?(FileAttachment) }

    assert_equal "The title of the attachment", edition.search_index['attachments'][index][:title]
    assert_equal "\nThis is a test pdf.\n\n\n", edition.search_index['attachments'][index][:content]
    assert_equal attachment.isbn, edition.search_index['attachments'][index][:isbn]
    assert_equal attachment.unique_reference, edition.search_index['attachments'][index][:unique_reference]
    assert_equal attachment.command_paper_number, edition.search_index['attachments'][index][:command_paper_number]
    assert_equal attachment.hoc_paper_number, edition.search_index['attachments'][index][:hoc_paper_number]
  end
end
