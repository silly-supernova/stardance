require "test_helper"

class Admin::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user(slack_id: "U_ADMIN_PROJECTS", display_name: "adminprojects")
    @admin.update!(granted_roles: %w[admin])

    @owner = create_user(slack_id: "U_ADMIN_PROJECT_OWNER", display_name: "adminprojectowner")
    @project = Project.create!(title: "Wrong Kind", hardware_stage: "design")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  test "admin can change project kind through the funding lock with audit log" do
    funding_request = @project.certification_funding_requests.new(
      user: @owner,
      complexity_tier: 1,
      requested_amount_cents: 5_000,
      status: :pending
    )
    funding_request.save!(validate: false)

    locked_project = @project.reload
    locked_project.hardware_stage = "build"
    assert_not locked_project.valid?
    assert_includes locked_project.errors[:hardware_stage], "cannot be changed after a funding request has been submitted"

    sign_in @admin

    assert_difference -> { PaperTrail::Version.where(item_type: "Project", item_id: @project.id.to_s).count }, 1 do
      patch update_hardware_stage_admin_project_path(@project), params: {
        hardware_stage: "build",
        reason: "Project was submitted as the wrong hardware stage after review."
      }
    end

    assert_redirected_to admin_project_path(@project)
    assert_equal "build", @project.reload.hardware_stage

    version = PaperTrail::Version.where(item_type: "Project", item_id: @project.id.to_s).order(:created_at).last
    assert_equal "admin_hardware_stage_update", version.event
    assert_equal @admin.id.to_s, version.whodunnit
    assert_equal [ "design", "build" ], version.object_changes["hardware_stage"]
    assert_equal "Project was submitted as the wrong hardware stage after review.", version.object_changes["reason"]
    assert_equal true, version.object_changes["funding_lock_bypassed"]
  end

  test "helper cannot change project kind" do
    helper = create_user(slack_id: "U_HELPER_PROJECTS", display_name: "helperprojects")
    helper.update!(granted_roles: %w[helper])
    sign_in helper

    patch update_hardware_stage_admin_project_path(@project), params: {
      hardware_stage: "build",
      reason: "Trying without permission."
    }, as: :json

    assert_response :forbidden
    assert_equal "design", @project.reload.hardware_stage
  end
end
