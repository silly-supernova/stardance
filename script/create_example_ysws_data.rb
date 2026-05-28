# Script to create example YSWS review data with realistic devlogs
# Run this in Rails console: load 'create_example_ysws_data.rb'

require 'open-uri'

puts "Starting example data creation..."
puts "This will create 10 devlogs (8 normal, 2 over 600 minutes) with images"

# Step 1: Find user 158
user = User.find_by(id: 158)
if user.nil?
  puts "❌ ERROR: User 158 not found. Aborting..."
  abort("User with ID 158 must exist before running this script.")
end
puts "Using existing user: #{user.id} (#{user.email})"

# Step 2: Create a project
project = Project.create!(
  title: "Test!",
  description: "Built a full-stack AI-powered task management app with real-time collaboration, smart prioritization, and custom integrations. Used React, Node.js, PostgreSQL, and OpenAI API. Features include drag-and-drop interface, dark mode, and mobile-responsive design.",
  demo_url: "https://hackclub.com",
  repo_url: "https://github.com/vandorena/portfolio",
  readme_url: "https://raw.githubusercontent.com/hackclub/stardance/main/README.md",
  ai_declaration: "Used AI for code suggestions (GitHub Copilot, ~15% of code)",
  ship_status: "approved",
  duration_seconds: 216000  # 60 hours total
)
puts "Created project: #{project.id} - #{project.title}"

# Step 3: Create project membership (make user the owner)
membership = Project::Membership.create!(
  user: user,
  project: project,
  role: :owner
)
puts "Created membership: User #{user.id} is owner of Project #{project.id}"

# Step 4: Create a ship event
ship_event = Post::ShipEvent.create!(
  body: "Shipping my project! Added new features and improvements.",
  certification_status: "approved"
)
puts "Created ship event: #{ship_event.id}"

# Step 5: Wrap ship event in a Post
ship_post = Post.create!(
  user: user,
  project: project,
  postable: ship_event
)
puts "Created ship post: #{ship_post.id}"

# Step 6: Create 10 devlogs with images from picsum
devlogs = []
devlog_data = [
  # 8 normal devlogs (under 600 minutes)
  {
    body: "Day 1: Started the project! Set up React app with Vite, configured Tailwind CSS, and created the basic layout. Super excited about this build!",
    duration: 5400,  # 90 minutes (1.5 hours)
  },
  {
    body: "Day 2: Built the authentication system with JWT tokens. Added login/signup pages and connected to backend API. Everything is working smoothly!",
    duration: 7200,  # 120 minutes (2 hours)
  },
  {
    body: "Day 3: Created the task list component with drag-and-drop using react-beautiful-dnd. Added filters and sorting. UI is looking clean!",
    duration: 10800,  # 180 minutes (3 hours)
  },
  {
    body: "Day 4: Integrated OpenAI API for smart task prioritization. The AI suggests which tasks to work on first based on deadlines and importance.",
    duration: 14400,  # 240 minutes (4 hours)
  },
  {
    body: "Day 5: Added real-time collaboration with WebSockets. Multiple users can now work on the same project and see updates live!",
    duration: 12600,  # 210 minutes (3.5 hours)
  },
  {
    body: "Day 6: Implemented dark mode with theme switching. Used CSS variables for easy theming. Looks amazing in both light and dark!",
    duration: 3600,  # 60 minutes (1 hour)
  },
  {
    body: "Day 7: Built the mobile-responsive design. Tested on different screen sizes and fixed all layout issues. Works great on phones!",
    duration: 9000,  # 150 minutes (2.5 hours)
  },
  {
    body: "Day 8: Added data visualization with recharts. Created dashboard showing productivity stats and task completion trends over time.",
    duration: 10800,  # 180 minutes (3 hours)
  },
  # 2 devlogs OVER 600 minutes (10 hours) - these should be highlighted in red!
  {
    body: "MEGA SESSION Day 9-10: Marathon coding weekend! Built the entire backend from scratch - Express.js server, PostgreSQL database, REST API with full CRUD operations, user authentication, data validation, error handling, and comprehensive testing. Also added email notifications and password reset functionality. This was intense but so worth it!",
    duration: 39600,  # 660 minutes (11 hours) - OVER LIMIT
  },
  {
    body: "FINAL PUSH Day 11-12: All-nighter to finish everything! Deployed to Vercel and Railway, configured custom domain, added SSL certificates, optimized performance with code splitting and lazy loading, fixed all bugs, wrote documentation, created demo video, and polished every detail. Project is now complete and live!",
    duration: 43200,  # 720 minutes (12 hours) - OVER LIMIT
  }
]

puts "\nDownloading images from picsum.photos and creating devlogs..."

devlog_data.each_with_index do |data, index|
  puts "\nCreating devlog #{index + 1}/#{devlog_data.length}..."

  # Download image from picsum.photos (random image, 1800px wide)
  image_url = "https://picsum.photos/1800/1200?random=#{index + rand(1000)}"
  puts "  Downloading image from: #{image_url}"

  begin
    image_data = URI.open(image_url).read
    temp_image = Tempfile.new(['devlog', '.jpg'])
    temp_image.binmode
    temp_image.write(image_data)
    temp_image.rewind

    # Create devlog
    devlog = Post::Devlog.new(
      body: data[:body],
      duration_seconds: data[:duration]
    )

    # Attach the image
    devlog.attachments.attach(
      io: File.open(temp_image.path),
      filename: "devlog_#{index + 1}.jpg",
      content_type: "image/jpeg"
    )

    devlog.save!
    devlogs << devlog

    minutes = data[:duration] / 60
    hours = (data[:duration] / 3600.0).round(1)
    over_limit = minutes > 600 ? " 🚨 OVER 600 MIN LIMIT!" : ""
    puts "  ✓ Created devlog #{index + 1}: ID=#{devlog.id}, #{minutes} minutes (#{hours}h)#{over_limit}"

    # Wrap devlog in a Post
    Post.create!(
      user: user,
      project: project,
      postable: devlog
    )

    temp_image.close
    temp_image.unlink

  rescue => e
    puts "  ✗ Error creating devlog #{index + 1}: #{e.message}"
    puts "  Skipping this devlog and continuing..."
  end
end

# Step 8: Create YSWS review
total_original_minutes = devlog_data.sum { |d| d[:duration] / 60 }
ysws_review = Certification::Ysws.create!(
  user: user,
  project: project,
  post_ship_event: ship_event,
  reviewer_id: nil,  # Will be assigned by guardian
  ship_cert_id: nil,  # Nil for reships as per handoff doc
  original_minutes: total_original_minutes,
  approved_minutes: nil,  # Will be set by reviewer
  reviewed_at: nil
)
puts "Created YSWS review: #{ysws_review.id}"
puts "  - Original minutes: #{ysws_review.original_minutes}"
puts "  - User: #{user.email}"
puts "  - Project: #{project.title}"

# Step 9: Create Certification::Devlog for each devlog (unreviewed - ready for review!)
puts "\nCreating devlog reviews..."
devlogs.each_with_index do |devlog, index|
  original_mins = devlog_data[index][:duration] / 60
  devlog_review = Certification::Devlog.create!(
    post_devlog: devlog,
    ysws_review: ysws_review,
    original_minutes: original_mins,
    approved_minutes: nil,  # Set to nil - needs review!
    justification: nil  # Will be filled by reviewer
  )
  over_limit = original_mins > 600 ? " 🚨 OVER LIMIT" : ""
  puts "  ✓ Devlog review #{index + 1}: ID=#{devlog_review.id}, #{original_mins} minutes#{over_limit}"
end
