require 'test_helper'

class InvestigationCUDTest < ActionDispatch::IntegrationTest
  include WriteApiTestSuite

  def model
    Investigation
  end

  def setup
    admin_login

    @min_project = Factory(:min_project)
    @min_project.title = 'Fred'

    @max_project = Factory(:max_project)
    @max_project.title = 'Bert'

    institution = Factory(:institution)
    current_person.add_to_project_and_institution(@min_project, institution)
    current_person.add_to_project_and_institution(@max_project, institution)

    @inv = Factory(:investigation, contributor: current_person, policy: Factory(:public_policy))
   end

  def post_values
    {
      project_ids:  [@min_project.id, @max_project.id],
      creator_ids: [@current_user.person.id]
    }
  end

  def patch_values
    {
      project_ids:  [@min_project.id, @max_project.id],
      creator_ids: [@current_user.person.id]
    }
  end

  test 'should not delete investigation with studies' do
    inv = Factory(:max_investigation)
    assert_no_difference('Investigation.count') do
      delete "/#{plural_name}/#{inv.id}.json"
      assert_response :forbidden
      validate_json response.body, '#/definitions/errors'
    end
  end

  test 'can delete an investigation with subscriptions' do
    inv = Factory(:investigation, policy: Factory(:public_policy, access_type: Policy::VISIBLE))
    p = Factory(:person)
    Factory(:subscription, person: inv.contributor, subscribable: inv)
    Factory(:subscription, person: p, subscribable: inv)

    user_login(inv.contributor)

    assert_difference('Subscription.count', -2) do
      assert_difference('Investigation.count', -1) do
        delete "/#{plural_name}/#{inv.id}.json"
      end
    end
  end
end
