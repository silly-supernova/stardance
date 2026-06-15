require "test_helper"

class OneTime::BackfillHardwareStageJobTest < ActiveJob::TestCase
  setup do
    @hardware = Project.create!(title: "Robot arm", project_type: "Hardware")
    @software = Project.create!(title: "Web app", project_type: "Web App")
    @staged   = Project.create!(title: "Funded robot", project_type: "Hardware", hardware_stage: "build")
  end

  test "dry run returns the candidates and writes nothing" do
    ids = OneTime::BackfillHardwareStageJob.new.perform(dry_run: true)

    assert_includes ids, @hardware.id
    assert_not_includes ids, @software.id, "software projects must not be classified as hardware"
    assert_not_includes ids, @staged.id, "projects already in the flow must be left alone"
    assert_nil @hardware.reload.hardware_stage, "dry run must not persist anything"
  end

  test "commit stamps design on AI-typed hardware projects only" do
    OneTime::BackfillHardwareStageJob.new.perform(dry_run: false)

    assert_equal "design", @hardware.reload.hardware_stage
    assert_nil @software.reload.hardware_stage
    assert_equal "build", @staged.reload.hardware_stage, "an existing stage must not be overwritten"
  end

  test "honors an explicit stage" do
    OneTime::BackfillHardwareStageJob.new.perform(dry_run: false, stage: "build")

    assert_equal "build", @hardware.reload.hardware_stage
  end

  test "rejects an unknown stage and writes nothing" do
    assert_raises(ArgumentError) do
      OneTime::BackfillHardwareStageJob.new.perform(dry_run: false, stage: "shipped")
    end

    assert_nil @hardware.reload.hardware_stage
  end

  test "classifies legacy rows that would fail today's validations" do
    legacy = Project.create!(title: "ok")
    legacy.update_column(:title, "x" * 200)        # now exceeds the 120-char limit
    legacy.update_column(:project_type, "Hardware")

    OneTime::BackfillHardwareStageJob.new.perform(dry_run: false)

    assert_equal "design", legacy.reload.hardware_stage
  end

  test "audits the change via paper trail attributed to the job" do
    skip "PaperTrail not enabled in this environment" unless PaperTrail.enabled?

    OneTime::BackfillHardwareStageJob.new.perform(dry_run: false)

    version = @hardware.reload.versions.last
    assert_equal OneTime::BackfillHardwareStageJob::WHODUNNIT, version.whodunnit
    assert_includes version.changeset.keys, "hardware_stage"
  end
end
