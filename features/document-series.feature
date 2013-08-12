Feature: Grouping documents into series
  As an organisation,
  I want to present regularly published documents as series
  So that my users can more easily find earlier publications of the same type

  Background:
    Given I am a writer in the organisation "Department of Beards"

  @javascript
  Scenario: Adding documents to a series
    Given a published policy "Blah blah" exists
    And a document series "Monthly Facial Topiary Update" exists
    Then I should be able to search for "Blah" and add the document to the series

  # # TODO: Can be simpified - no need to publish, just visit frontend
  # Scenario: Documents should link back to their series
  #   When I create a document called "May 2012 Update" in the "Monthly Facial Topiary Update" series
  #   And someone publishes the document "May 2012 Update"
  #   When I visit the publication "May 2012 Update"
  #   Then I should see links back to the "Monthly Facial Topiary Update" series

  # # TODO: Needs reworking - documents are now added via a different interface
  # Scenario: Series list all their documents
  #   Given I create a document called "May 2012 Update" in the "Monthly Facial Topiary Update" series
  #   And I create a document called "June 2012 Update" in the "Monthly Facial Topiary Update" series
  #   And someone publishes the document "May 2012 Update"
  #   And someone publishes the document "June 2012 Update"
  #   When I view the "Monthly Facial Topiary Update" series
  #   Then I should see a summary of the series clearly displayed
  #   Then I should see links to all the documents in the "Monthly Facial Topiary Update" series

  # # TODO: No longer relavant, TBK
  # Scenario: Editors should not be overwhelmed by series from other organisations
  #   Given series from several other organisations exist
  #   When I begin drafting a new publication "Title doesn't matter"
  #   Then I should see the series from "Department of Beards" first in the series list
