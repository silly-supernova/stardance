GITHUB_STICKERS = ShopItem::GITHUB_STICKERS
NASA_STICKERS = ShopItem::NASA_STICKERS
HC_STICKERS = ShopItem::HC_STICKERS

STICKER_PACKS = [
  { name: "Random Sticker Pack", description: "5 random stickers: 1 github, 1 nasa, 3 hack club", ticket_cost: 10,
    agh_contents: [
      { "random_from" => GITHUB_STICKERS, "quantity" => 1 },
      { "random_from" => NASA_STICKERS, "quantity" => 1 },
      { "random_from" => HC_STICKERS, "quantity" => 3 }
    ] },
  { name: "Sticker Pack A", description: "5 curated stickers: 1 github, 1 nasa, 3 hack club", ticket_cost: 15,
    agh_contents: [
      { "random_from" => GITHUB_STICKERS, "quantity" => 1 },
      { "random_from" => NASA_STICKERS, "quantity" => 1 },
      { "random_from" => %w[Sti/Bra/Cas/Mix Sti/Bra/Hei/Cof Sti/Bra/Orp/Plu Sti/Bra/Ins/1st Sti/Bra/Con/Rod], "quantity" => 3 }
    ] },
  { name: "Sticker Pack B", description: "5 curated stickers: 1 github, 1 nasa, 3 hack club", ticket_cost: 15,
    agh_contents: [
      { "random_from" => GITHUB_STICKERS, "quantity" => 1 },
      { "random_from" => NASA_STICKERS, "quantity" => 1 },
      { "random_from" => %w[Sti/Bra/BMO/Ovr Sti/Bra/Hel/Nam Sti/Bra/O&H/Lap Sti/Bra/Ene/Drk Sti/Sti/Fla/Top], "quantity" => 3 }
    ] },
  { name: "Sticker Pack C", description: "5 curated stickers: 1 github, 1 nasa, 3 hack club", ticket_cost: 15,
    agh_contents: [
      { "random_from" => GITHUB_STICKERS, "quantity" => 1 },
      { "random_from" => NASA_STICKERS, "quantity" => 1 },
      { "random_from" => %w[Sti/Bra/Tam/1st Sti/Bra/Hei/Gmr Sti/Bra/Orp/Des Sti/Bra/Cap/Hck Sti/Bra/Yak/Bot], "quantity" => 3 }
    ] },
  { name: "Sticker Pack D", description: "5 curated stickers: 1 github, 1 nasa, 3 hack club", ticket_cost: 15,
    agh_contents: [
      { "random_from" => GITHUB_STICKERS, "quantity" => 1 },
      { "random_from" => NASA_STICKERS, "quantity" => 1 },
      { "random_from" => %w[Sti/Bra/CD-/Gra Sti/Bra/Hei/Pls Sti/Bra/Orp/Cos Sti/Bra/Ram/1st Sti/Bra/Lic/Plt], "quantity" => 3 }
    ] },
  { name: "Sticker Pack E", description: "5 curated stickers: 1 github, 1 nasa, 3 hack club", ticket_cost: 15,
    agh_contents: [
      { "random_from" => GITHUB_STICKERS, "quantity" => 1 },
      { "random_from" => NASA_STICKERS, "quantity" => 1 },
      { "random_from" => %w[Sti/Bra/Sur/Sum Sti/Bra/Hei/Spe Sti/Sti/Orp/Thu Sti/Bra/Fla/Emb Sti/Bra/Clo/1st], "quantity" => 3 }
    ] },
  { name: "Sticker Pack F", description: "5 curated stickers: 1 github, 1 nasa, 3 hack club", ticket_cost: 15,
    agh_contents: [
      { "random_from" => GITHUB_STICKERS, "quantity" => 1 },
      { "random_from" => NASA_STICKERS, "quantity" => 1 },
      { "random_from" => %w[Sti/Bra/Can/Let Sti/Bra/Hei/Lea Sti/Bra/O&H/Hug Sti/Bra/The/1st Sti/Bra/Ray/1st], "quantity" => 3 }
    ] },
  { name: "Sticker Pack G", description: "5 curated stickers: 1 github, 1 nasa, 3 hack club", ticket_cost: 15,
    agh_contents: [
      { "random_from" => GITHUB_STICKERS, "quantity" => 1 },
      { "random_from" => NASA_STICKERS, "quantity" => 1 },
      { "random_from" => %w[Sti/Bra/Und/Sta Sti/Bra/Hei/Trs Sti/Bra/Pol/O&H Sti/Sti/Hac/1st Sti/Bra/Gan/Gan], "quantity" => 3 }
    ] },
  { name: "Sticker Pack H", description: "5 curated stickers: 1 github, 1 nasa, 3 hack club", ticket_cost: 15,
    agh_contents: [
      { "random_from" => GITHUB_STICKERS, "quantity" => 1 },
      { "random_from" => NASA_STICKERS, "quantity" => 1 },
      { "random_from" => %w[Sti/Sti/Kaw/1st Sti/Bra/Hei/Chi Sti/Bra/Pol/Se2 Sti/Bra/HC-/CD-], "quantity" => 3 }
    ] }
].freeze

PLACEHOLDER_IMAGE_PATH = Rails.root.join("app/assets/images/free_sticker.avif") unless defined?(PLACEHOLDER_IMAGE_PATH)

STICKER_PACKS.each do |pack|
  attrs = pack.merge(type: "ShopItem::WarehouseItem", enabled: true)
  item = ShopItem.find_or_initialize_by(name: attrs[:name], type: attrs[:type])
  item.assign_attributes(attrs)
  unless item.image.attached?
    item.image.attach(io: File.open(PLACEHOLDER_IMAGE_PATH), filename: "placeholder.avif", content_type: "image/avif")
  end
  item.save!
end
