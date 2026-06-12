require "test_helper"

class ProjectVoteDebtBypassTest < ActiveSupport::TestCase
  setup do
    @owner = create_user(slack_id: "U_DEBT_OWNER", display_name: "debtowner")
    @owner.update!(vote_balance: -3)
    @project = Project.create!(title: "indebted", description: "d")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  teardown do
    Flipper.disable(:week_2_release)
  end

  def vote_balance_requirement
    @project.shipping_requirements.find { |r| r[:key] == :vote_balance }
  end

  def create_mission_with_prize
    mission = create_mission
    prize_item = shop_items(:one)
    prize_item.update_column(:mission_prize_only, true)
    mission.prizes.create!(shop_item: prize_item)
    mission
  end

  test "vote_balance requirement fails with debt and no mission attached" do
    refute vote_balance_requirement[:passed]
  end

  test "vote_balance requirement is bypassed for a fixed-stardust mission ship" do
    mission = create_mission
    mission.update!(fixed_stardust_payout: 50)
    @project.attach_mission!(mission)

    assert vote_balance_requirement[:passed]
  end

  test "vote_balance requirement is bypassed for a direct-prize mission ship" do
    mission = create_mission_with_prize
    @project.attach_mission!(mission)

    assert vote_balance_requirement[:passed]
  end

  test "vote_balance requirement still fails for a mission without a fixed payout" do
    @project.attach_mission!(create_mission)

    refute vote_balance_requirement[:passed]
  end

  test "vote_balance requirement still fails for a shop-unlock-only mission" do
    mission = create_mission
    mission.shop_unlocks.create!(shop_item: shop_items(:one))
    @project.attach_mission!(mission)

    refute vote_balance_requirement[:passed]
  end

  test "vote_balance requirement still fails when the owner already redeemed the mission's prize" do
    mission = create_mission_with_prize
    @project.attach_mission!(mission)

    other_project = Project.create!(title: "earlier win", description: "d")
    other_project.memberships.create!(user: @owner, role: :owner)
    submission = ship_to_mission!(other_project, @owner, mission)
    order = ShopOrder.new(user: @owner, shop_item: mission.prizes.first.shop_item, quantity: 1)
    order.save!(validate: false)
    submission.update_column(:shop_order_id, order.id)

    refute vote_balance_requirement[:passed]
  end

  test "vote_balance requirement still fails once week_2_release is on for the owner" do
    mission = create_mission
    mission.update!(fixed_stardust_payout: 50)
    @project.attach_mission!(mission)
    Flipper.enable_actor(:week_2_release, @owner)

    refute vote_balance_requirement[:passed]
  end

  test "vote_balance requirement still fails when the project already shipped to the mission" do
    mission = create_mission
    mission.update!(fixed_stardust_payout: 50)
    @project.attach_mission!(mission)
    ship_to_mission!(@project, @owner, mission)

    refute vote_balance_requirement[:passed]
  end

  test "vote_balance requirement still fails when the owner completed the mission elsewhere" do
    mission = create_mission
    mission.update!(fixed_stardust_payout: 50)
    @project.attach_mission!(mission)

    other_project = Project.create!(title: "earlier win", description: "d")
    other_project.memberships.create!(user: @owner, role: :owner)
    ship_to_mission!(other_project, @owner, mission, status: "approved")

    refute vote_balance_requirement[:passed]
  end
end
