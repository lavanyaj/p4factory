#include "includes/headers.p4"
#include "includes/parser.p4"
#include "includes/tables.p4"

/* METADATA */
header_type ingress_metadata_t {
    fields {
        is_multicast : 1;
        is_routable : 1;
	mc_idx : 16;
	drop_code : 16;
    }
}

metadata ingress_metadata_t ingress_metadata;

control ingress {
 apply(mac_learning);
 apply(routable);
 
if (ingress_metadata.is_routable == 1 and
   ingress_metadata.is_multicast == 0) {
  apply(multicast_routing);
  apply(igmp);
 } 

if (ingress_metadata.is_routable == 1 and
   ingress_metadata.is_multicast == 0) {
  apply(unicast_routing);
  }

if (ingress_metadata.is_multicast == 0) {
 apply(switching);
 apply(acl);
 }
}

