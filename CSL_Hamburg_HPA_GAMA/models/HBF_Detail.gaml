/***
* Name: HBFDetail
* Author: JLo
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model HBFDetail

global {
	string cityGISFolder <- "./../external/";
	
	file shapefile_hbf <- file(cityGISFolder + "Hbf-Detail.shp");
	file shapefile_walking_paths <- file(cityGISFolder + "Detail_Walking Areas.shp");
	file shapefile_public_transportation <- file(cityGISFolder + "Detail_Public Transportation.shp");
	file shapefile_sprinters <- file(cityGISFolder + "Detail_Sprinters.shp");
	file shapefile_shuttle <- file(cityGISFolder + "Detail_Bus Shuttle.shp");
	file shapefile_entry_points <- file(cityGISFolder + "Detail_Entry Points Platforms.shp");
	geometry shape <- envelope(shapefile_walking_paths);
	float step <- 2 #s;
	int current_hour update: (time / #hour) mod 24;
	
	int nb_people <- 50;
	int nb_tourists <- 200;
	int nb_taxis <- 20;
	int nb_shuttle <- 2;
	int nb_sprinters <- 1;
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	int maximal_turn <- 135; //in degree
	int cohesion_factor <- 5;
	float people_size <- 2.0;
	int coming_train;
	
	reflex update { //trains arriving randomly
		coming_train <- rnd(10);
	}

	init{
		create hbf from: shapefile_hbf;
		create metro from: shapefile_public_transportation;
		create sprinter_spot from: shapefile_sprinters;
		create shuttle_spot from: shapefile_shuttle;
		create entry_points from: shapefile_entry_points with: [platform::int(read("platform_s"))]; //number of platform taken from shapefile
		create walking_area from: shapefile_walking_paths {
			//Creation of the free space by removing the shape of the buildings (train station complex)
			free_space <- geometry(walking_area - (hbf + people_size));
		}
		free_space <- free_space simplification(1.0);
		
		create people number: nb_people {
		speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
		target_loc <- point(one_of(metro));
		location <- point(one_of(entry_points));
		}	
	}
}
species hbf{
	rgb color <- #gray;	
	aspect base {
		draw shape color: color;
	}
}

species metro{
	rgb color <- #red;	
	aspect base {
		draw square(4) color: color;
	}
}

species sprinter_spot{
	rgb color <- #blue;	
	aspect base {
		draw square(4) color: color;
	}
}

species shuttle_spot{
	rgb color <- #blue;	
	aspect base {
		draw square(4) color: color;
	}
}

species entry_points{
	rgb color<-#black;	
	bool has_train <- false;
	int platform; ////////////////////////////7IT DOESN'T READ THE SHAPEFILE: SHOWS NILL
	int incoming_train <- nil ;
	
	reflex train {
		incoming_train <- coming_train;
		write platform;
		if (incoming_train = platform) {
			has_train <- true;
			write has_train;
			color <- #green;
			create species(people) number: 20{
				location <- self.location; ////////////////////////IT CREATES PEOPLE IN RANDOM PLACES, NOT IN THE ENTRY POINTS
			}	//people coming by train
		}
	}
	
	aspect base {
		draw square(4) color: color;
	}
}

species walking_area{
	rgb color <- #pink;	
	float transparency <- 0.5;
	aspect base {
		draw shape color: color;
	}
}

species people skills:[moving] {
	point target_loc;
	float speed <- 5 + rnd(1000) / 1000;
	point velocity <- {0,0};
	float heading max: heading + maximal_turn min: heading - maximal_turn;
	float size <- people_size; 
	rgb color <- #black;
		
	//Reflex to change target when arrived
	reflex end when: location distance_to target_loc <= 2 * people_size{
		//target_loc<-one_of(metro);
		do die;
	}
	//Reflex to compute the velocity of the agent considering the cohesion factor
	reflex follow_goal  {
		velocity <- velocity + ((target_loc - location) / cohesion_factor);
	}
	//Reflex to apply separation when people are too close from each other
	reflex separation {
		point acc <- {0,0};
		ask (people at_distance size)  {
			acc <- acc - (location - myself.location);
		}  
		velocity <- velocity + acc;
	}
	//Reflex to avoid the different obstacles
	reflex avoid { 
		point acc <- {0,0};
		list<hbf> nearby_obstacles <- (hbf at_distance people_size);
		loop obs over: nearby_obstacles {
			acc <- acc - (obs.location - location); 
		}
		velocity <- velocity + acc; 
	}
	//Reflex to move the agent considering its location, target and velocity
	reflex move {
		point old_location <- copy(location);
		do goto target: location + velocity;
		if not(self overlaps free_space ) {
			location <- ((location closest_points_with free_space)[1]);
		}
		velocity <- location - old_location;
	}	
	
	aspect default {
		draw pyramid(size) color: color;
		draw sphere(size/3) at: {location.x,location.y,size} color: color;
	}
}

experiment "PCM_Simulation" type: gui {
	font regular <- font("Helvetica", 14, # bold);
	output {

		display map type:java2D 
		{
			species hbf aspect:base;
			species metro aspect: base ;
			species sprinter_spot aspect: base ;
			species shuttle_spot aspect: base ;
			species entry_points aspect: base;
			species people;
			species walking_area aspect:base transparency:0.8;
		}
	}
}
