#include "includes/headers.p4"
#include "includes/parser.p4"

control ingress {
 
apply(mac_learning);
apply(routable);

if (is_routable == TRUE) {
 if (mcast_pkt == TRUE) {
  apply(multicast_routing);
  apply(igmp);
  exit();
 } else  {
  apply(unicast_routing);
  }
}


apply(switching)
apply(acl)

}

