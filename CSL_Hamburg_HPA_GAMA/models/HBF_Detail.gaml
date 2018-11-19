/***
* Name: HBFDetail
* Author: JLopez
* Description: The model aims to represent the movement of people and tourists in the tran station and surounding area. People arrive by train and go to random destinations. Tourist arrive by train and go to (1) taxi (2) luggage dropoff area and (3) take bus shuttle.
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
	float step <- 1 #s;
	int current_hour update: (time / #hour) mod 24;
	
	int nb_people<- rnd(7)+5;
	int nb_tourist <- rnd(2)+1;
	int nb_taxis <- 20;
	int nb_shuttle <- 2;
	int nb_sprinters <- 1;
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	int maximal_turn <- 360; //in degree
	int cohesion_factor_ppl <- 1; //must be more than 0
	int cohesion_factor_tou <- 10;
	float people_size <- 2.0;
	int coming_train;
	int nb_people_existing;
	int luggage_drop<-0;
	
	reflex update { 
		coming_train <- rnd(500)+rnd(700); //trains arriving randomly
		nb_people_existing <- length(list(people));
		luggage_drop <- int(tourist count(each.dropped_luggage));
	}

	init{
		create hbf from: shapefile_hbf;
		create metro from: shapefile_public_transportation;
		create sprinter_spot from: shapefile_sprinters;
		create shuttle_spot from: shapefile_shuttle;
		create entry_points from: shapefile_entry_points with: [platform_nb::int(read("platform_s"))]; //number of platform should be taken from shapefile
		create walking_area from: shapefile_walking_paths {
			//Creation of the free space by removing the shape of the buildings (train station complex)
			free_space <- geometry(walking_area - (hbf + people_size));
		}
		free_space <- free_space simplification(1.0);
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
	int platform_nb;
	
	reflex train {
		if (coming_train = platform_nb) {
			has_train <- true;
			color <- #green;
			
			create species(people) number: nb_people{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				target_loc <- point(one_of(metro));
				location <- point(myself);
			}	
			create species(tourist) number: nb_tourist{
			speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			target_loc <- point(one_of(sprinter_spot));
			location <- point(myself);
			}	
		}
		else {
				color <- #black;
		}
	}	
	
	aspect base {
		draw square(4) color: color;
	}
}

species walking_area{
	rgb color <- #pink;	
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
	reflex end when: location distance_to target_loc <= 5 * people_size{
		do die;
	}
	//Reflex to compute the velocity of the agent considering the cohesion factor
	reflex follow_goal  {
		velocity <- velocity + ((target_loc - location) / cohesion_factor_ppl);
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
		list<hbf> nearby_obstacles <- (hbf at_distance (4 * people_size));
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

species tourist skills:[moving] {
	point target_loc;
	float speed <- 5 + rnd(1000) / 1000;
	point velocity <- {0,0};
	float heading max: heading + maximal_turn min: heading - maximal_turn;
	float size <- people_size; 
	rgb color <- #orange;
	bool dropped_luggage;
		
	//Reflex to change target when arrived
	reflex end when: location distance_to target_loc <= 2 * people_size and dropped_luggage = false{
		target_loc <- point(one_of(shuttle_spot));
		dropped_luggage <- true;
		write "luggage dropped";
	}
	reflex board when: location distance_to target_loc <= 2 * people_size and dropped_luggage = true{
		write "bus shuttle taken";
		do die;
	}
	//Reflex to compute the velocity of the agent considering the cohesion factor
	reflex follow_goal  {
		velocity <- velocity + ((target_loc - location) / cohesion_factor_tou);
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
		display graph refresh:every(1#mn){
			chart "tourist in the city" type: series size:{1,0.5} position: {0,0} {
				data "Drop off luggage" value: luggage_drop color: #orange;
				data "People in the station" value: nb_people_existing color: #black;
			}
		}
		display map type:java2D 
		{
			species hbf aspect:base;
			species metro aspect: base ;
			species sprinter_spot aspect: base ;
			species shuttle_spot aspect: base ;
			species people;
			species tourist;
			species walking_area aspect:base transparency:0.9 ;
		}
	}
}
