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

  test "admin can clear the latest ship and reset the project to draft" do
    ship_event = Post::ShipEvent.create!(body: "Shipped as software", certification_status: "returned", hours_at_ship: 1)
    Post.create!(project: @project, user: @owner, postable: ship_event)
    @project.ship_reviews.create!(status: :returned, feedback: "Please switch this to hardware.")
    @project.update_column(:ship_status, "needs_changes")

    sign_in @admin

    assert_difference [ "Post::ShipEvent.count", "Certification::Ship.count" ], -1 do
      post clear_latest_ship_admin_project_path(@project), params: {
        reason: "Converted to hardware; clearing the bad software ship."
      }
    end

    assert_redirected_to admin_project_path(@project)
    @project.reload
    assert_equal "draft", @project.ship_status
    assert_nil @project.last_ship_event

    version = PaperTrail::Version.where(item_type: "Project", item_id: @project.id.to_s).order(:created_at).last
    assert_equal "admin_clear_latest_ship", version.event
    assert_equal [ "needs_changes", "draft" ], version.object_changes["ship_status"]
    assert_equal "Converted to hardware; clearing the bad software ship.", version.object_changes["reason"]
  end

  test "clearing a ship also removes the YSWS review it generated" do
    ship_event = Post::ShipEvent.create!(body: "Approved ship", certification_status: "approved", hours_at_ship: 1)
    Post.create!(project: @project, user: @owner, postable: ship_event)
    review = @project.ship_reviews.create!(status: :approved, reviewer: @admin)
    Certification::Ysws.create!(
      post_ship_event: ship_event,
      ship_cert: review,
      project: @project,
      user: @owner,
      original_minutes: 60
    )
    @project.update_column(:ship_status, "approved")

    sign_in @admin

    assert_difference [ "Post::ShipEvent.count", "Certification::Ship.count", "Certification::Ysws.count" ], -1 do
      post clear_latest_ship_admin_project_path(@project), params: {
        reason: "Wrong kind; clearing the approved ship and its YSWS review."
      }
    end

    assert_redirected_to admin_project_path(@project)
    assert_equal "draft", @project.reload.ship_status
  end

  test "cannot clear a ship that has already paid out" do
    ship_event = Post::ShipEvent.create!(body: "Paid", certification_status: "approved", hours_at_ship: 1, payout: 42.0)
    Post.create!(project: @project, user: @owner, postable: ship_event)
    @project.update_column(:ship_status, "approved")

    sign_in @admin

    assert_no_difference "Post::ShipEvent.count" do
      post clear_latest_ship_admin_project_path(@project), params: { reason: "trying to clear a paid ship" }
    end

    assert_redirected_to admin_project_path(@project)
    assert_equal "approved", @project.reload.ship_status
  end

  test "clearing the latest ship requires a reason" do
    ship_event = Post::ShipEvent.create!(body: "x", certification_status: "returned", hours_at_ship: 1)
    Post.create!(project: @project, user: @owner, postable: ship_event)

    sign_in @admin

    assert_no_difference "Post::ShipEvent.count" do
      post clear_latest_ship_admin_project_path(@project), params: { reason: "   " }
    end

    assert_redirected_to admin_project_path(@project)
  end

  test "helper cannot clear the latest ship" do
    ship_event = Post::ShipEvent.create!(body: "x", certification_status: "returned", hours_at_ship: 1)
    Post.create!(project: @project, user: @owner, postable: ship_event)

    helper = create_user(slack_id: "U_HELPER_CLEAR", display_name: "helperclear")
    helper.update!(granted_roles: %w[helper])
    sign_in helper

    assert_no_difference "Post::ShipEvent.count" do
      post clear_latest_ship_admin_project_path(@project), params: { reason: "no perms" }, as: :json
    end

    assert_response :forbidden
  end
end
