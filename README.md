# S&Box Grass

My attempt at making grass for S&Box. This was mainly for me to get to know compute and regular shaders better and how they work. 

# Includes:
### Frustum Culling
### Changing far grass with low LOD ones
### Occlusion Culling (works but very noticable in certain cases)
### View Independent Thickening (If you try to look at the edge of a blade it will thicken it to make it look fuller) 
### Grass interaction with the player

------------------------------------------------------
My main issue currently is how the grass looks from afar as it does not really look quite good and also the color does not match of the color of the high LOD grass. Another thing is I have no idea how to make grass spawn only on specific spots of the terrain and not others, looked into it but couldn't get it to work properly and looked awful.

I am just experimenting and this repository is here for maybe someone in the future who wants to try and has no idea how to start so hopefully this will help.


Here are some examples of what it looks like:
<img width="1903" height="924" alt="image" src="https://github.com/user-attachments/assets/666f764c-2261-4a55-abd5-900fb0166e82" />
<img width="1918" height="923" alt="image" src="https://github.com/user-attachments/assets/61aa02b5-231c-463e-b4ce-5cc839b45c00" />


# Frustum Culling:


https://github.com/user-attachments/assets/e7c17094-87cb-4946-989b-cb0608b800f7

# View Independent Thickening (Works but still has artifacts but is quite hard to notice in an entire field.



https://github.com/user-attachments/assets/8563b805-69b4-4ef9-a1ef-32ff4bb34209


### With view independent thickening:
<img width="1919" height="940" alt="image" src="https://github.com/user-attachments/assets/e1a7ee9b-2c86-4007-b473-0f4d9a4dc502" />

### Without view independent thickening:
<img width="1912" height="939" alt="image" src="https://github.com/user-attachments/assets/9360c98e-93bb-4244-b8e0-202580a9a77c" />

Below is a video. (720p cause I can't upload 1080p, the grass looks better in the editor vs this video due to due quality)



https://github.com/user-attachments/assets/a6a5a058-1408-4027-afb8-bb88b3f35f83


