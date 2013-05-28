#include "squid.h"
#include "acl/Acl.h"
#include "acl/BoolOps.h"
#include "acl/Checklist.h"
#include "acl/Gadgets.h"
#include "acl/InnerNode.h"
#include "cache_cf.h"
#include "ConfigParser.h"
#include "Debug.h"
#include "globals.h"
#include "wordlist.h"
#include <algorithm>

// "delete acl" class to use with std::for_each() in InnerNode::~InnerNode()
class AclDeleter
{
public:
    void operator()(ACL* acl) {
        // Do not delete explicit ACLs; they are maintained by Config.aclList.
        if (acl && !acl->registered)
            delete acl;
    }
};

Acl::InnerNode::~InnerNode()
{
    std::for_each(nodes.begin(), nodes.end(), AclDeleter());
}

void
Acl::InnerNode::prepareForUse()
{
    std::for_each(nodes.begin(), nodes.end(), std::mem_fun(&ACL::prepareForUse));
}

bool
Acl::InnerNode::empty() const
{
    return nodes.empty();
}

void
Acl::InnerNode::add(ACL *node)
{
    assert(node != NULL);
    nodes.push_back(node);
}

// one call parses one "acl name acltype name1 name2 ..." line
// kids use this method to handle [multiple] parse() calls correctly
void
Acl::InnerNode::lineParse()
{
    // XXX: not precise, may change when looping or parsing multiple lines
    if (!cfgline)
        cfgline = xstrdup(config_input_line);

    // expect a list of ACL names, each possibly preceeded by '!' for negation

    while (const char *t = ConfigParser::strtokFile()) {
        const bool negated = (*t == '!');
        if (negated)
            ++t;

        debugs(28, 3, "looking for ACL " << t);
        ACL *a = ACL::FindByName(t);

        if (a == NULL) {
            debugs(28, DBG_CRITICAL, "ACL not found: " << t);
            self_destruct();
            return;
        }

        // append(negated ? new NotNode(a) : a);
        if (negated)
            add(new NotNode(a));
        else
            add(a);
    }

    return;
}

wordlist*
Acl::InnerNode::dump() const
{
    wordlist *values = NULL;
    for (Nodes::const_iterator i = nodes.begin(); i != nodes.end(); ++i)
        wordlistAdd(&values, (*i)->name);
    return values;
}

int
Acl::InnerNode::match(ACLChecklist *checklist)
{
    return doMatch(checklist, nodes.begin());
}

bool
Acl::InnerNode::resumeMatchingAt(ACLChecklist *checklist, Nodes::const_iterator pos) const
{
    debugs(28, 5, "checking " << name << " at " << (pos-nodes.begin()));
    const int result = doMatch(checklist, pos);
    const char *extra = checklist->asyncInProgress() ? " async" : "";
    debugs(28, 3, "checked: " << name << " = " << result << extra);

    // merges async and failures (-1) into "not matched"
    return result == 1;
}