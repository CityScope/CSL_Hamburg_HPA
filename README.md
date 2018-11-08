# CSL_Hamburg_HPA
Code and documentation for HCU CSL + MIT CS HPA project 


## Description

The Prot City Model should represent the following situation: When people is ‘departing’, they arrive at the station by train with their luggage. Some of them proceed to a drop-off area, where they can check-in their luggage directly. Luggage is sent via sprinters (vans) to the cruise terminals. Once without luggage, people walk towards the bus station and take a private shuttle to the cruise terminal. The period in between dropping the luggage and taking the bus shuttle constitutes a potential visit to the city center, depending on the time window (to be on time to take the cruise). 

People that decide not to drop-off the luggage in advance proceed directly to take the same bus shuttle to the cruise terminal and leave the luggage in the trunk. Depending on the cruise brand and the social organization of people (couples, families, small groups), they take taxis to the terminals when available. The price is cheaper than the bus shuttle, but their availability is limited. Taxis depart from the same parking as where the luggage drop-off area is located. 

Taxis, bus shuttles and luggage sprinters are running from the station to the cruise terminals and vice-versa. They they drop ‘departing’ passengers on the terminals, they also pick ‘arriving’ passengers and take them back to the Central Station. These passengers travel together with their luggage from the cruise terminal the train station and take the train back home. People disembark the vessel between 7 and 10am, and board between 11:30am and 5pm. In those periods where the likeliness to have a round trip for a taxi driver is lower (early morning only arrival and late afternoon only departure), then their willingness to travel to the terminals decreases and the availability of taxis too. Luggage sprinters and bus shuttles run even when empty. 

Each vessel has between 800 and 4500 people capacity, and up to 4 vessels can be operating at the same time in the 3 terminals (HafenCity terminal will be able to handle up to 2 mid-size vessels). That means that the model should be operate with minimum 1600 (one small-size vessel) and maximum 27000 (two large and two mid-size vessels) cruise passengers arriving/departing each day.

Data about arrival times, transportation choice, time spent in the city, amount of pieces of luggage, etc. is provided by Cruise Gate Hamburg and Aida Cruises, which the model should use as first input.

