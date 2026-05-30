require "test_helper"

class GuidesControllerTest < ActionDispatch::IntegrationTest
  test "index renders for anonymous visitors" do
    get resources_path
    assert_response :success
    assert_select ".guides-index__title", text: "Guides"
  end

  test "index lists every registered guide" do
    get resources_path
    assert_response :success
    Guide.all.each do |guide|
      assert_select ".guide-card__title", text: guide.title
    end
  end

  test "show renders each registered guide" do
    Guide.all.each do |guide|
      get resource_path(guide.slug)
      assert_response :success, "GET #{resource_path(guide.slug)} should return 200"
      assert_select ".guide-article__title", text: guide.title
    end
  end

  test "show 404s on unknown slug" do
    get resource_path("definitely-not-a-real-guide")
    assert_response :not_found
  end

  test "how_to_ship embeds the decision tree controller and full node payload" do
    get resource_path(:how_to_ship)
    assert_response :success
    assert_select '[data-controller="decision-tree"]'
    assert_select "[data-decision-tree-nodes-value]"
    assert_select "[data-decision-tree-root-value]", { value: ShipDecisionTree::ROOT_ID }
  end

  test "ShipDecisionTree exposes a complete graph" do
    nodes = ShipDecisionTree::NODES
    assert nodes.key?(ShipDecisionTree::ROOT_ID), "root node must exist"

    nodes.each do |id, node|
      next if id == ShipDecisionTree::ROOT_ID
      parent = node[:parent]
      assert parent && nodes.key?(parent), "node #{id} parent #{parent.inspect} must exist"
    end

    nodes.each do |id, node|
      next unless node[:type] == :question
      node[:choices].each do |choice|
        assert nodes.key?(choice[:id]), "choice #{choice[:id]} (from #{id}) must reference an existing node"
      end
    end
  end
end
