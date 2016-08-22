require_relative 'lib/instagram/instagram-stories-api'

# Get Instagram Stories
instagram = InstagramStoriesAPI.new()
@user_stories = instagram.get_user_stories()
@stories = instagram.get_stories()
