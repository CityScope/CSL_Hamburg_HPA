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
	
	int nb_people<- rnd(5)+1;
	int nb_tourist <- rnd(0)+1;
	int nb_taxis <- 20;
	int nb_shuttle <- 2;
	int nb_sprinters <- 1;
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	int maximal_turn <- 30; //in degree
	int cohesion_factor_ppl <- 1; //must be more than 0
	int cohesion_factor_tou <- 100;
	float people_size <- 2.0;
	int coming_train;
	int nb_people_existing;
	int luggage_drop<-0;
	
	float perception_distance <- 300.0 parameter: true;
	int precision <- 120 parameter: true;
	
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
			free_space <- geometry(walking_area);
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

species tourist skills:[moving] control:fsm {
	point target_loc;
	float speed <- 5 + rnd(1000) / 1000;
	point velocity <- {0,0};
	float heading max: heading + maximal_turn min: heading - maximal_turn;
	float size <- people_size; 
	rgb color <- #orange;
	bool dropped_luggage;
	
	bool knows_where_to_go;
	geometry perceived_area;
	point target;
		
	//Reflex to change target when arrived
	reflex drop_off when: location distance_to target_loc <= 2 * people_size and dropped_luggage = false{
		target_loc <- point(one_of(shuttle_spot));
		dropped_luggage <- true;
		knows_where_to_go <- true;
		write "luggage dropped";
	}
	reflex board when: location distance_to target_loc <= 2 * people_size and dropped_luggage = true{
		write "bus shuttle taken";
		do die;
	}
	//Reflex to compute the velocity of the agent considering the cohesion factor
	reflex follow_goal  {
		velocity <- velocity + ((target - location) / cohesion_factor_tou);
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
		list<hbf> nearby_obstacles <- (hbf at_distance (10*people_size));
		loop obs over: nearby_obstacles {
			acc <- acc - (obs.location - location); 
		}
		velocity <- velocity + acc; 
	}
	
	action depart {
		if knows_where_to_go = true {
			point old_location <- copy(location);
			do goto target: target_loc on: (free_space);
			if not(self overlaps free_space ) {
			location <- ((location closest_points_with free_space)[1]);
			}
			velocity <- location - old_location;
		}
	}
	
	action arrive { //if they the drop_off area, they go there. If they don't, they look for it.
		if (target_loc intersects perceived_area) {
			knows_where_to_go <- true;
		} else {
			point old_location <- copy(location);
			do goto target: (any_location_in(perceived_area intersection geometry(walking_area))) on: (free_space);
			if not(self overlaps free_space ) {
			location <- ((location closest_points_with free_space)[1]);
			}
			velocity <- location - old_location;	
		}
	}	
	
	state departing{
		enter{
			knows_where_to_go <- true;
			perceived_area <- nil;
		}
		do depart;
	}
	
	state arriving initial: true {
		do arrive;
		do update_perception;
		transition to: departing when: knows_where_to_go = true;
	}
	
	
	//computation of the perceived area
	action update_perception {
		//the agent perceived a cone (with an amplitude of 60°) at a distance of  perception_distance (the intersection with the world shape is just to limit the perception to the world)
		perceived_area <- (cone(heading-30,heading+30) intersection world.shape) intersection circle(perception_distance); 
		
		//if the perceived area is not nil, we use the masked_by operator to compute the visible area from the perceived area according to the obstacles
		if (perceived_area != nil) {
			perceived_area <- perceived_area masked_by (hbf,precision);

		}
	}
	
	aspect default {
		draw pyramid(size) color: color;
	}
	aspect perception {
		if (perceived_area != nil) {
			draw perceived_area color: #magenta;
			}
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
			species tourist aspect: default;
			species tourist aspect: perception transparency:0.97;
			species walking_area aspect:base transparency:0.9 ;
		}
	}
}
