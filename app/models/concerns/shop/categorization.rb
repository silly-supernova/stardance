# frozen_string_literal: true

# DB-backed lookup for the top-level shop categories on the hub. Categories
# describe *what an item is* (grants, hardware, digital, merch, games);
# fulfilment origin lives separately on `Shop::Source`. The two are independent
# — an item carries both. "all" is a synthetic virtual category materialised
# by `Shop::Category.all_virtual`.
module Shop::Categorization
  module_function

  def all
    [ Shop::Category.all_virtual, *Shop::Category.ordered ]
  end

  def find(slug)
    Shop::Category.find_by_slug(slug.to_s)
  end

  def title_for(slug)
    find(slug)&.title || "Shop"
  end

  def filter(items, slug)
    category = find(slug)
    return items if category.nil? || category.virtual_all?

    category.filter(items)
  end
end
